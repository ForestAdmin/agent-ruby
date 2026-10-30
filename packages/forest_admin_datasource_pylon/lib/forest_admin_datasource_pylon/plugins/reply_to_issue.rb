module ForestAdminDatasourcePylon
  module Plugins
    # Answers a Pylon issue from Forest, on the channel the customer used, or
    # posts an internal note on it. Pylon keeps the channel: a reply is
    # delivered into the conversation of the message it names, which
    # ReplyTarget picks. Email is the exception Pylon leaves to the caller,
    # which must name the recipients.
    #
    # SINGLE scope only: the form is built from one issue's thread.
    class ReplyToIssue < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction      = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope     = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      NAME = 'Reply to Pylon issue'.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        options = {} unless options.is_a?(Hash)
        datasource = options[:datasource]
        raise ForestException, 'ReplyToIssue plugin requires :datasource' unless datasource
        raise ForestException, 'ReplyToIssue plugin requires a collection' unless collection_customizer

        opts = {
          issue_id_field: options[:issue_id_field],
          allow_internal_note: options.fetch(:allow_internal_note, true) ? true : false,
          support_emails: normalize_emails(options[:support_emails])
        }

        collection_customizer.add_action((options[:action_name] || NAME).to_s, build_action(datasource, opts))
      end

      private

      def normalize_emails(value)
        Array(value).map { |email| email.to_s.strip.downcase }.reject(&:empty?).uniq
      end

      def build_action(datasource, opts)
        BaseAction.new(scope: ActionScope::SINGLE, form: FormBuilder.build(datasource, opts),
                       &executor(datasource, opts))
      end

      # The thread is read again rather than trusted from the form: the
      # conversation may have moved since it was rendered.
      def executor(datasource, opts)
        lambda do |context, result_builder|
          state = ThreadLookup.call(datasource, context, opts)
          next result_builder.error(message: state.error) if state.error

          body = context.form_values[FormBuilder::MESSAGE_LABEL].to_s
          next result_builder.error(message: 'A message is required.') if body.strip.empty?

          status, message = if FormBuilder.public_reply?(context, opts)
                              reply(datasource, state, body, context.form_values, opts)
                            else
                              note(datasource, state, body)
                            end
          result_builder.public_send(status, message: message)
        end
      end

      def reply(datasource, state, body, values, opts)
        return [:error, no_target_message(state.issue_id, opts)] if state.target.nil?

        payload = { 'body_html' => body, 'message_id' => state.target.message_id }
        if state.target.email?
          to = addresses(values[FormBuilder::TO_LABEL])
          return [:error, 'At least one recipient (To) is required to reply by email.'] if to.empty?

          payload['email_info'] = { 'to_emails' => to, 'cc_emails' => addresses(values[FormBuilder::CC_LABEL]) }
        end

        write(state.issue_id, reply_success(state, payload)) do
          datasource.client.reply_to_issue(state.issue_id, payload)
        end
      end

      def note(datasource, state, body)
        write(state.issue_id, "Internal note added to Pylon issue #{state.issue_id}.") do
          datasource.client.create_issue_note(state.issue_id, 'body_html' => body)
        end
      end

      # A 4xx is Pylon naming what is wrong with this reply, handed to the
      # operator as the action's error. Anything else stays the failure it is.
      def write(issue_id, success)
        yield
        [:success, success]
      rescue APIError => e
        raise unless (400..499).cover?(e.status.to_i)

        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Pylon refused to write on issue #{issue_id}: #{e.message}"
        )
        [:error, e.message]
      end

      def addresses(value)
        Array(value).map { |address| address.to_s.strip }.reject(&:empty?).uniq(&:downcase)
      end

      def no_target_message(issue_id, opts)
        message = "Pylon issue #{issue_id} has no customer-visible message, so it cannot get a public reply."
        opts[:allow_internal_note] ? "#{message} Post an internal note instead." : message
      end

      def reply_success(state, payload)
        signed = 'signed by the account of the Pylon API token'
        if payload['email_info']
          return "Reply emailed to #{payload["email_info"]["to_emails"].join(", ")} on Pylon issue " \
                 "#{state.issue_id}, #{signed}."
        end

        "Reply sent via #{state.target.channel_label} on Pylon issue #{state.issue_id}, #{signed}."
      end
    end
  end
end
