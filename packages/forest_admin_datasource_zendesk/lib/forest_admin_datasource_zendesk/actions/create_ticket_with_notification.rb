require 'cgi'

module ForestAdminDatasourceZendesk
  module Actions
    # Smart action that opens a Zendesk ticket from any host collection. The
    # selected record needs no relation to Zendesk: the requester is identified
    # by an email entered (or pre-filled) in the form, and Zendesk creates the
    # user record on the fly if it doesn't already exist.
    #
    # ZendeskUser auto-registers this action with a resolver that pre-fills the
    # requester email from the user's `email` field. To expose the action on
    # any other collection (e.g. a Postgres `customers` table customized via
    # the agent), call `register_on` from the agent setup:
    #
    #   ForestAdminDatasourceZendesk::Actions::CreateTicketWithNotification
    #     .register_on(customer, datasource,
    #                  default_subject: 'Refund for {{record.email}}',
    #                  default_message: '<p>Hi {{record.name}},</p>',
    #                  requester_email_default: ->(record) { record['email'] })
    #
    # `requester_email_default` accepts either:
    #   * a String — used as a literal email default (static), or
    #   * a Proc `record -> email_string` — evaluated against the selected
    #     record when the form opens (dynamic).
    #
    # `ticket_id_field` (register_on only) names a writable field on the host
    # collection that receives the freshly-created ticket id. The update is
    # best-effort: a failure (missing field, validation error, etc.) is logged
    # and surfaced in the success message but doesn't roll back the ticket.
    #
    # The Message field uses Forest's RichText widget and ships as `html_body`.
    # Subject and Message defaults support `{{record.<field>}}` tokens resolved
    # against the selected record when the form opens.
    module CreateTicketWithNotification
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAME = 'Create ticket and notify'.freeze
      TOKEN_RE = /\{\{\s*record\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

      module_function

      # All-kwargs registration — the ParameterLists cop counts each kwarg
      # toward its 5-param limit, which doesn't really apply to named args.
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

      # Returns one of :skipped, :ok, or [:failed, "reason"]. The host record
      # update is best-effort: a writeback failure mustn't roll back the ticket
      # we already created Zendesk-side, so we surface the issue in the success
      # message and the agent log instead of erroring out.
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

      # `escape_html` matters for the Message template, which is rendered as HTML
      # by the Zendesk comment endpoint (and possibly emailed to the requester).
      # Without escaping, a record value containing `<`, `&`, or markup would
      # break the layout or, worse, smuggle markup into the outbound email.
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

        # Ticket created Zendesk-side, but the writeback to the host collection failed.
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
