module ForestAdminDatasourcePylon
  module Plugins
    # Answers a Pylon issue from Forest, on the channel the customer used, or
    # posts an internal note on it. Pylon keeps the channel: a reply is
    # delivered into the conversation of the message it names, which
    # ReplyTarget picks. Email is the exception Pylon leaves to the caller,
    # which must name the recipients.
    #
    # SINGLE scope only: the form is built from one issue's thread.
    #
    # With `post_as_operator`, a public reply is signed by the Pylon user
    # sharing the Forest operator's email, and refused when there is none.
    # Internal notes are always signed by the token's account.
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
          post_as_operator: options[:post_as_operator] ? true : false,
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

      # A note needs the issue only. A reply reads the thread again rather than
      # trusting the form: the conversation may have moved since it rendered.
      def executor(datasource, opts)
        lambda do |context, result_builder|
          issue_id = ThreadLookup.issue_id(context, opts)
          next result_builder.error(message: ThreadLookup.no_issue(opts[:issue_id_field])) if issue_id.nil?

          body = context.form_values[FormBuilder::MESSAGE_LABEL].to_s
          next result_builder.error(message: 'A message is required.') if blank_html?(body)

          status, message = if FormBuilder.public_reply?(context, opts)
                              reply(datasource, ThreadLookup.read(datasource, issue_id, opts), body, context, opts)
                            else
                              note(datasource, issue_id, body)
                            end
          result_builder.public_send(status, message: message)
        end
      end

      # An emptied rich-text editor still submits markup such as `<p><br></p>`.
      def blank_html?(body)
        return false if body.match?(/<img\b/i)

        body.gsub(/<[^>]*>/, ' ').gsub(/&nbsp;|&#160;/i, ' ').strip.empty?
      end

      def reply(datasource, state, body, context, opts)
        return [:error, state.error] if state.error
        return [:error, no_target_message(state.issue_id, opts)] if state.target.nil?

        payload = { 'body_html' => body, 'message_id' => state.target.message_id }
        if state.target.email?
          to = addresses(context.form_values[FormBuilder::TO_LABEL])
          return [:error, 'At least one recipient (To) is required to reply by email.'] if to.empty?

          payload['email_info'] = { 'to_emails' => to,
                                    'cc_emails' => addresses(context.form_values[FormBuilder::CC_LABEL]) }
        end

        operator = OperatorLookup.call(datasource, context.caller) if opts[:post_as_operator]
        return [:error, operator.error] if operator&.error

        payload['user_id'] = operator.user['id'] if operator
        write(state.issue_id, 'reply', reply_success(state, payload, operator&.user)) do
          datasource.client.reply_to_issue(state.issue_id, payload)
        end
      end

      def note(datasource, issue_id, body)
        write(issue_id, 'internal note', "Internal note added to Pylon issue #{issue_id}.") do
          datasource.client.create_issue_note(issue_id, 'body_html' => body)
        end
      end

      # A 4xx is Pylon naming what is wrong, handed over as it is. Anything else
      # may have failed after Pylon delivered the message, so the operator is
      # told to check before sending it again rather than shown a bare failure.
      def write(issue_id, what, success)
        yield
        [:success, success]
      rescue APIError => e
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] #{what} on issue #{issue_id} failed: #{e.message}"
        )
        return [:error, e.message] if (400..499).cover?(e.status.to_i)

        [:error, "Pylon did not confirm the #{what} on issue #{issue_id} (#{e.message}). It may have been " \
                 'delivered: check the issue in Pylon before sending it again.']
      end

      def addresses(value)
        ReplyTarget.unique_addresses(Array(value))
      end

      def no_target_message(issue_id, opts)
        message = "Pylon issue #{issue_id} has no customer-visible message, so it cannot get a public reply."
        opts[:allow_internal_note] ? "#{message} Post an internal note instead." : message
      end

      def reply_success(state, payload, operator)
        signed = if operator
                   "signed by #{operator["name"] || operator["email"]}"
                 else
                   'signed by the account of the Pylon API token'
                 end
        if payload['email_info']
          return "Reply emailed to #{payload["email_info"]["to_emails"].join(", ")} on Pylon issue " \
                 "#{state.issue_id}, #{signed}."
        end

        "Reply sent via #{state.target.channel_label} on Pylon issue #{state.issue_id}, #{signed}."
      end
    end
  end
end
