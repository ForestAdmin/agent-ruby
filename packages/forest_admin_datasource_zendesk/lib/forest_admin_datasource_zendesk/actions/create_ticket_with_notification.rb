require 'cgi'

module ForestAdminDatasourceZendesk
  module Actions
    # Zendesk creates the requester user automatically from the form's email,
    # so the host record needs no relation to Zendesk and the action can be
    # `register_on`'d on any collection.
    module CreateTicketWithNotification
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAME = 'Create ticket and notify'.freeze
      TOKEN_RE = /\{\{\s*record\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

      module_function

      def register_on(collection, datasource, default_subject: nil, default_message: nil, # rubocop:disable Metrics/ParameterLists
                      requester_email_default: nil, ticket_id_field: nil)
        collection.add_action(NAME, build(datasource,
                                          default_subject: default_subject,
                                          default_message: default_message,
                                          requester_email_default: requester_email_default,
                                          ticket_id_field: ticket_id_field))
      end

      def build(datasource, default_subject: nil, default_message: nil,
                requester_email_default: nil, ticket_id_field: nil)
        BaseAction.new(
          scope: ActionScope::SINGLE,
          form: form(default_subject, default_message, requester_email_default),
          &executor(datasource, ticket_id_field)
        )
      end

      def form(default_subject, default_message, requester_email_default)
        [
          { type: FieldType::STRING, label: 'Requester email', is_required: true,
            description: 'Email of the Zendesk requester. Pre-filled from the selected record when available.',
            default_value: requester_default(requester_email_default) },
          { type: FieldType::STRING, label: 'Subject', is_required: true,
            default_value: template_default(default_subject, escape_html: false) },
          { type: FieldType::STRING, label: 'Message', widget: 'RichText', is_required: true,
            description: 'Sent as the ticket\'s first comment (HTML). Public comments trigger the ' \
                         'default Zendesk notification email to the requester.',
            default_value: template_default(default_message, escape_html: true) },
          { type: FieldType::ENUM, label: 'Priority', enum_values: Collections::Ticket::ENUM_PRIORITY,
            default_value: 'normal' },
          { type: FieldType::ENUM, label: 'Type', enum_values: Collections::Ticket::ENUM_TYPE },
          { type: FieldType::BOOLEAN, label: 'Send as internal note',
            description: 'When checked, the first comment is private and no email is sent to the requester.',
            default_value: false }
        ]
      end

      def executor(datasource, ticket_id_field = nil)
        lambda do |context, result_builder|
          values = context.form_values
          email  = values['Requester email']
          next result_builder.error(message: 'Requester email is required.') unless present?(email)

          ticket = datasource.client.create_ticket(build_payload(values, email))
          ticket_id = ticket.respond_to?(:[]) ? ticket['id'] : nil

          writeback = write_back_ticket_id(context, ticket_id_field, ticket_id)
          result_builder.success(message: success_message(ticket_id, values, writeback))
        end
      end

      # Best-effort: a writeback failure mustn't roll back the ticket we
      # already created Zendesk-side.
      def write_back_ticket_id(context, field, ticket_id)
        return :skipped if field.nil? || ticket_id.nil?

        context.collection.update(context.filter, { field => ticket_id })
        :ok
      rescue StandardError => e
        ForestAdminDatasourceZendesk.logger.warn(
          "[forest_admin_datasource_zendesk] failed to store ticket id in '#{field}': #{e.class}: #{e.message}"
        )
        [:failed, "#{e.class}: #{e.message}"]
      end

      def build_payload(values, email)
        internal_note = truthy?(values['Send as internal note'])
        payload = {
          'requester' => { 'email' => email },
          'subject' => values['Subject'],
          'comment' => { 'html_body' => values['Message'], 'public' => !internal_note }
        }
        payload['priority'] = values['Priority'] if present?(values['Priority'])
        payload['type'] = values['Type'] if present?(values['Type'])
        payload
      end

      def requester_default(value)
        return nil if value.nil?
        return value if value.is_a?(String)

        lambda do |context|
          record = fetch_record(context)
          record.empty? ? nil : value.call(record)
        rescue StandardError => e
          ForestAdminDatasourceZendesk.logger.warn(
            "[forest_admin_datasource_zendesk] requester_email_default resolver raised: #{e.class}: #{e.message}"
          )
          nil
        end
      end

      def template_default(template, escape_html:)
        return nil unless present?(template)
        return template unless template.match?(TOKEN_RE)

        ->(context) { interpolate(template, fetch_record(context), escape_html: escape_html) }
      end

      def fetch_record(context)
        context.get_record([]) || {}
      rescue StandardError => e
        ForestAdminDatasourceZendesk.logger.warn(
          "[forest_admin_datasource_zendesk] failed to fetch record for token interpolation: #{e.class}: #{e.message}"
        )
        {}
      end

      # Message ships as html_body; an unescaped `<` or `&` from a record value
      # would break the outbound email or smuggle markup into it.
      def interpolate(template, record, escape_html:)
        template.gsub(TOKEN_RE) do
          key = ::Regexp.last_match(1)
          value = record[key] || record[key.to_sym]
          next '' if value.nil?

          escape_html ? CGI.escapeHTML(value.to_s) : value.to_s
        end
      end

      def success_message(ticket_id, values, writeback = :skipped)
        base = base_success_message(ticket_id, values)
        return base unless writeback.is_a?(Array) && writeback.first == :failed

        "#{base} (warning: could not store the ticket id on the record: #{writeback.last})"
      end

      def base_success_message(ticket_id, values)
        if truthy?(values['Send as internal note'])
          ticket_id ? "Ticket ##{ticket_id} created (internal note, no email)." : 'Ticket created (internal note).'
        else
          ticket_id ? "Ticket ##{ticket_id} created and requester notified." : 'Ticket created and requester notified.'
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
