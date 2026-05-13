require 'cgi'

module ForestAdminDatasourceZendesk
  module Actions
    # Zendesk creates the requester user automatically from the form's email,
    # so the host record needs no relation to Zendesk and the action can be
    # `register_on`'d on any collection.
    module CreateTicketWithNotification # rubocop:disable Metrics/ModuleLength
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAME = 'Create ticket and notify'.freeze
      NO_TEMPLATE = 'No template'.freeze
      TOKEN_RE = /\{\{\s*record\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

      module_function

      def register_on(collection, datasource, **opts)
        collection.add_action(opts[:action_name] || NAME, build(datasource, **opts.except(:action_name)))
      end

      def build(datasource, **opts)
        opts[:email_templates] = Array(opts[:email_templates]).compact
        BaseAction.new(scope: ActionScope::SINGLE, form: form(opts), &executor(datasource, opts))
      end

      # When email_templates are configured the form becomes a two-page wizard
      # (template selection, then the prefilled body). Otherwise the original
      # flat form is used. The ActionCollectionDecorator rejects forms that mix
      # pages with non-page elements, so we keep each mode strictly homogeneous.
      def form(opts)
        body = body_fields(opts)
        return body if opts[:email_templates].empty?

        [
          { type: 'Layout', component: 'Page', next_button_label: 'Continue',
            elements: [template_field(opts[:email_templates])] },
          { type: 'Layout', component: 'Page', previous_button_label: 'Back',
            elements: body }
        ]
      end

      def body_fields(opts)
        fields = [requester_field(opts[:requester_email_default]),
                  subject_field(opts[:default_subject]),
                  message_field(opts[:default_message], opts[:email_templates])]
        fields << priority_field unless present?(opts[:priority_override])
        fields << type_field unless present?(opts[:type_override])
        fields << internal_note_field
        fields
      end

      def executor(datasource, opts = {})
        lambda do |context, result_builder|
          values = context.form_values
          email  = values['Requester email']
          next result_builder.error(message: 'Requester email is required.') unless present?(email)

          payload = build_payload(values, email, opts)
          ticket = datasource.client.create_ticket(payload)
          ticket_id = ticket.respond_to?(:[]) ? ticket['id'] : nil

          writeback = write_back_ticket_id(context, opts[:ticket_id_field], ticket_id)
          result_builder.success(message: success_message(ticket_id, values, writeback))
        end
      end

      def build_payload(values, email, opts = {})
        internal_note = truthy?(values['Send as internal note'])
        payload = {
          'requester' => { 'email' => email },
          'subject' => values['Subject'],
          'comment' => { 'html_body' => values['Message'], 'public' => !internal_note }
        }
        priority = present?(opts[:priority_override]) ? opts[:priority_override] : values['Priority']
        type     = present?(opts[:type_override])     ? opts[:type_override]     : values['Type']
        payload['priority'] = priority if present?(priority)
        payload['type']     = type     if present?(type)
        payload
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

      def requester_field(default)
        { type: FieldType::STRING, label: 'Requester email', is_required: true,
          description: 'Email of the Zendesk requester. Pre-filled from the selected record when available.',
          default_value: requester_default(default) }
      end

      def template_field(templates)
        { type: FieldType::ENUM, label: 'Template', is_required: true,
          enum_values: [NO_TEMPLATE] + templates.map { |t| t[:title] },
          default_value: NO_TEMPLATE,
          description: 'Pick a template to pre-fill the Message on the next page.' }
      end

      def subject_field(default_subject)
        { type: FieldType::STRING, label: 'Subject', is_required: true,
          default_value: template_default(default_subject, escape_html: false) }
      end

      def message_field(default_message, templates)
        field = { type: FieldType::STRING, label: 'Message', widget: 'RichText', is_required: true,
                  description: 'Sent as the ticket\'s first comment (HTML). Public comments trigger the ' \
                               'default Zendesk notification email to the requester.' }
        return field.merge(default_value: template_default(default_message, escape_html: true)) if templates.empty?

        # `value:` (not `default_value:`) — drop_default only runs when data
        # doesn't already have the key, but after the first render the agent
        # caches Message='' in data, so a default_value proc would never re-fire
        # on Template change. `value:` is re-evaluated by drop_deferred on every
        # form fetch.
        field.merge(value: message_value(templates))
      end

      def priority_field
        { type: FieldType::ENUM, label: 'Priority',
          enum_values: Collections::Ticket::ENUM_PRIORITY, default_value: 'normal' }
      end

      def type_field
        { type: FieldType::ENUM, label: 'Type', enum_values: Collections::Ticket::ENUM_TYPE }
      end

      def internal_note_field
        { type: FieldType::BOOLEAN, label: 'Send as internal note',
          description: 'When checked, the first comment is private and no email is sent to the requester.',
          default_value: false }
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

      # Returns the template content (with `{{record.X}}` tokens interpolated
      # against the host record) when Template was just changed by the user;
      # returns nil otherwise so the agent's set_watch_changes carries over the
      # current Message input. 'No template' (or any unknown title) yields ''.
      def message_value(templates)
        by_title = templates.to_h { |t| [t[:title], t[:content].to_s] }
        lambda do |context|
          return nil unless context.field_changed?('Template')

          title = context.get_form_value('Template')
          return '' if title == NO_TEMPLATE

          content = by_title[title].to_s
          return content unless content.match?(TOKEN_RE)

          interpolate(content, fetch_record(context), escape_html: true)
        end
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
