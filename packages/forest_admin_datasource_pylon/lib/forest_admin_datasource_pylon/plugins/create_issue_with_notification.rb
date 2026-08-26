module ForestAdminDatasourcePylon
  module Plugins
    # Opens a Pylon issue and delivers its first message to the requester.
    #
    # Pylon creates the contact on the fly from the form's email, so the action
    # can be registered on any host collection — no relation to Pylon needed.
    #
    # Where Zendesk notifies as a side effect of a public comment, Pylon says it
    # outright: `destination_metadata.destination` names the channel the
    # issue's `body_html` is delivered through, and no `destination_metadata` at
    # all is what leaves the issue internal. The "Send as internal note"
    # checkbox is that choice, worded the way the Zendesk plugin words it.
    #
    # The form is FormBuilder's, the wire payload is Payload's; what is left
    # here is the registration, its options, and what the operator reads back.
    class CreateIssueWithNotification < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction      = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope     = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      NAME = 'Create Pylon issue and notify'.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        options = {} unless options.is_a?(Hash)
        datasource = options[:datasource]
        raise ForestException, 'CreateIssueWithNotification plugin requires :datasource' unless datasource
        raise ForestException, 'CreateIssueWithNotification plugin requires a collection' unless collection_customizer

        opts = options.except(:datasource)
        opts[:email_templates] = normalize_templates(opts[:email_templates])
        opts[:destination] = normalize_destination(opts[:destination])
        opts[:priority_override] = normalize_priority(opts[:priority_override])
        require_sender_email!(opts)

        collection_customizer.add_action(opts[:action_name] || NAME, build_action(datasource, opts))
      end

      private

      # The title is what the enum carries and what the content is looked up
      # by, so it has to name one template: a duplicate makes the first
      # unreachable and would send the other one's content under its name, and
      # the sentinel of the "pick nothing" option makes the template it names
      # unpickable. Both are configuration, so both are refused at registration
      # rather than discovered by whoever sends the wrong message.
      def normalize_templates(value)
        templates = Array(value).compact
        titles = templates.map { |template| template[:title].to_s }

        reserved = titles.include?(FormBuilder::NO_TEMPLATE)
        raise ForestException, "An email template cannot be titled #{FormBuilder::NO_TEMPLATE.inspect}." if reserved

        duplicated = titles.tally.select { |_title, count| count > 1 }.keys
        raise ForestException, "Duplicate email template titles: #{duplicated.join(", ")}." if duplicated.any?

        templates
      end

      def normalize_destination(value)
        return Payload::EMAIL_DESTINATION if value.nil?

        normalize(value, IssueEnums::DESTINATION, 'destination')
      end

      # `POST /issues` refuses an email delivery that does not name the address it
      # is sent from, so the option is mandatory there rather than optional. The
      # refusal belongs at registration, where it names the option and the agent
      # will not boot without it, rather than at the first execution, where it
      # reaches the operator as a Pylon 400 on a form they filled correctly.
      def require_sender_email!(opts)
        return unless opts[:destination] == Payload::EMAIL_DESTINATION
        return if Payload.present?(opts[:sender_email])

        raise ForestException,
              'CreateIssueWithNotification requires :sender_email when the destination is email. ' \
              'It must be one of the addresses configured in the Pylon email app.'
      end

      def normalize_priority(value)
        return nil unless Payload.present?(value)

        normalize(value, IssueEnums::PRIORITY, 'priority')
      end

      def normalize(value, allowed, label)
        normalized = value.to_s
        return normalized if allowed.include?(normalized)

        raise ForestException,
              "Unknown CreateIssueWithNotification #{label}: #{normalized}. Allowed: #{allowed.join(", ")}."
      end

      def build_action(datasource, opts)
        BaseAction.new(scope: ActionScope::SINGLE, form: FormBuilder.build(opts), &executor(datasource, opts))
      end

      def executor(datasource, opts)
        lambda do |context, result_builder|
          values = context.form_values
          email  = values['Requester email']
          next result_builder.error(message: 'Requester email is required.') unless Payload.present?(email)

          issue = create_issue(datasource, Payload.build(values, email, opts))
          next result_builder.error(message: issue.last) if issue.is_a?(Array)

          writeback = write_back_issue_id(context, opts[:issue_id_field], issue['id'])
          result_builder.success(message: success_message(issue, values, opts, writeback))
        end
      end

      # A 4xx is Pylon naming what the operator filled in, and reaches them as
      # the action's own error, message intact: raised, it would leave the agent
      # to answer 'Unexpected error' — APIError is none of the classes whose
      # message the translator passes through — and to log nothing either, its
      # status being under 500. Anything else is Pylon or the network failing,
      # which no edit of the form would change, and stays the 500 it is.
      def create_issue(datasource, payload)
        datasource.client.create_issue(payload)
      rescue APIError => e
        raise unless (400..499).cover?(e.status.to_i)

        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Pylon refused the issue creation: #{e.message}"
        )
        [:rejected, e.message]
      end

      # Best-effort: Pylon has no transaction to roll back, and the issue exists
      # whether or not the host record could be stamped with its id.
      def write_back_issue_id(context, field, issue_id)
        return :skipped if field.nil?

        context.collection.update(context.filter, { field => issue_id })
        :ok
      rescue StandardError => e
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] failed to store the issue id in '#{field}': #{e.class}: #{e.message}"
        )
        [:failed, "#{e.class}: #{e.message}"]
      end

      def success_message(issue, values, opts, writeback)
        base = base_success_message(issue, values, opts)
        return base unless writeback.is_a?(Array) && writeback.first == :failed

        "#{base} (warning: could not store the issue id on the record: #{writeback.last})"
      end

      # The number is what an operator recognises an issue by; the id stands in
      # when Pylon answered without one.
      def base_success_message(issue, values, opts)
        reference   = issue['number'] || issue['id']
        destination = Payload.destination_for(values, opts)
        if Payload.internal?(destination)
          return "Issue ##{reference} created (internal, the requester was not contacted)."
        end

        "Issue ##{reference} created and the requester notified by #{destination.tr("_", " ")}."
      end
    end
  end
end
