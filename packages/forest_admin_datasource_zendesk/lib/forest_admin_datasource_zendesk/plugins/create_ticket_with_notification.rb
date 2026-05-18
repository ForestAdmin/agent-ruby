module ForestAdminDatasourceZendesk
  module Plugins
    # Zendesk creates the requester user on the fly from the form's email,
    # so the action can be registered on any host collection — no relation
    # to Zendesk needed.
    class CreateTicketWithNotification < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction      = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope     = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      NAME = 'Create ticket and notify'.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        raise ForestException, 'CreateTicketWithNotification plugin requires :datasource' unless datasource
        raise ForestException, 'CreateTicketWithNotification plugin requires a collection' unless collection_customizer

        opts = options.except(:datasource)
        opts[:email_templates] = Array(opts[:email_templates]).compact
        collection_customizer.add_action(opts[:action_name] || NAME, build_action(datasource, opts))
      end

      private

      def build_action(datasource, opts)
        BaseAction.new(scope: ActionScope::SINGLE, form: FormBuilder.build(opts), &executor(datasource, opts))
      end

      def executor(datasource, opts)
        lambda do |context, result_builder|
          values = context.form_values
          email  = values['Requester email']
          next result_builder.error(message: 'Requester email is required.') unless present?(email)

          payload = build_payload(values, email, opts)
          ticket_id = datasource.client.create_ticket(payload)['id']

          writeback = write_back_ticket_id(context, opts[:ticket_id_field], ticket_id)
          result_builder.success(message: success_message(ticket_id, values, writeback))
        end
      end

      def build_payload(values, email, opts)
        internal_note = truthy?(values['Send as internal note'])
        payload = {
          # Zendesk's create-user-on-the-fly requires a non-empty `name`;
          # derive from the email's local-part. Ignored if the user exists.
          'requester' => { 'email' => email, 'name' => derive_requester_name(email) },
          'subject' => values['Subject'],
          'comment' => { 'html_body' => values['Message'], 'public' => !internal_note }
        }
        priority = present?(opts[:priority_override]) ? opts[:priority_override] : values['Priority']
        type     = present?(opts[:type_override])     ? opts[:type_override]     : values['Type']
        payload['priority']  = priority             if present?(priority)
        payload['type']      = type                 if present?(type)
        # Zendesk's `recipient` = the support address replies come FROM.
        payload['recipient'] = opts[:sender_email] if present?(opts[:sender_email])
        payload
      end

      def derive_requester_name(email)
        local = email.to_s.split('@').first.to_s
        local.empty? ? email.to_s : local
      end

      # Best-effort: a writeback failure mustn't roll back the Zendesk ticket.
      def write_back_ticket_id(context, field, ticket_id)
        return :skipped if field.nil?

        context.collection.update(context.filter, { field => ticket_id })
        :ok
      rescue StandardError => e
        ForestAdminDatasourceZendesk.logger.warn(
          "[forest_admin_datasource_zendesk] failed to store ticket id in '#{field}': #{e.class}: #{e.message}"
        )
        [:failed, "#{e.class}: #{e.message}"]
      end

      def success_message(ticket_id, values, writeback = :skipped)
        base = base_success_message(ticket_id, values)
        return base unless writeback.is_a?(Array) && writeback.first == :failed

        "#{base} (warning: could not store the ticket id on the record: #{writeback.last})"
      end

      def base_success_message(ticket_id, values)
        if truthy?(values['Send as internal note'])
          "Ticket ##{ticket_id} created (internal note, no email)."
        else
          "Ticket ##{ticket_id} created and requester notified."
        end
      end

      def truthy?(value)
        value == true || value.to_s.casecmp('true').zero?
      end

      def present?(value)
        !value.nil? && value.to_s != ''
      end
    end
  end
end
