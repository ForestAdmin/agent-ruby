require 'cgi'

module ForestAdminDatasourcePylon
  module Plugins
    class CreateIssueWithNotification
      module FormBuilder
        FieldType = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

        NO_TEMPLATE = 'No template'.freeze
        TOKEN_RE = /\{\{\s*record\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

        module_function

        # ActionCollectionDecorator rejects forms that mix Page elements with
        # non-Page elements, so each mode (flat / wizard) stays homogeneous.
        def build(opts)
          body = body_fields(opts)
          return body if opts[:email_templates].empty?

          [
            { type: 'Layout', component: 'Page', next_button_label: 'Continue',
              elements: [template_field(opts[:email_templates])] },
            { type: 'Layout', component: 'Page', previous_button_label: 'Back',
              elements: body }
          ]
        end

        # No Type field, unlike the Zendesk form: `POST /issues` does not take
        # one -- Pylon accepts `type` on an update only, which is what
        # `Issue::UPDATE_ONLY` already says.
        def body_fields(opts)
          fields = [requester_field(opts[:requester_email_default]),
                    subject_field(opts[:default_subject]),
                    message_field(opts[:default_message], opts[:email_templates])]
          fields << priority_field unless present?(opts[:priority_override])
          fields << internal_note_field if opts[:show_internal_note]
          fields
        end

        def requester_field(default)
          { type: FieldType::STRING, label: 'Requester email', is_required: true,
            description: 'Email of the Pylon requester; the contact is created on the fly when it is unknown. ' \
                         'Pre-filled from the selected record when available.',
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
                    description: 'The body of the issue (HTML). Unless it is sent as an internal note, this is ' \
                                 'the message Pylon delivers to the requester.' }
          return field.merge(default_value: template_default(default_message, escape_html: true)) if templates.empty?

          # `value:` (not `default_value:`) — drop_default runs once (data
          # key sticks after the first render); drop_deferred re-evaluates
          # on every fetch, so Template changes re-fire the message proc.
          field.merge(value: message_value(templates))
        end

        # No default: Pylon applies its own when the key is absent, and no
        # priority is ever read back — the issue payload does not carry one, so
        # nothing in Forest will show the operator what they picked.
        def priority_field
          { type: FieldType::ENUM, label: 'Priority', enum_values: IssueEnums::PRIORITY,
            description: 'Set on creation only; Pylon does not return the priority of an issue, so it is not ' \
                         'shown anywhere in Forest afterwards.' }
        end

        def internal_note_field
          { type: FieldType::BOOLEAN, label: 'Send as internal note',
            description: 'When checked, the issue is created without contacting the requester.',
            default_value: false }
        end

        def requester_default(value)
          return nil if value.nil?
          return template_default(value, escape_html: false) if value.is_a?(String)

          lambda do |context|
            record = fetch_record(context)
            record.empty? ? nil : value.call(record)
          rescue StandardError => e
            ForestAdminDatasourcePylon.logger.warn(
              "[forest_admin_datasource_pylon] requester_email_default resolver raised: #{e.class}: #{e.message}"
            )
            nil
          end
        end

        def template_default(template, escape_html:)
          return nil unless present?(template)
          return template unless template.match?(TOKEN_RE)

          ->(context) { interpolate(template, fetch_record(context), escape_html: escape_html) }
        end

        # Returns nil unless Template was just changed, so set_watch_changes
        # carries over the user's current Message edits between renders.
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
          ForestAdminDatasourcePylon.logger.warn(
            "[forest_admin_datasource_pylon] failed to fetch record for token interpolation: #{e.class}: #{e.message}"
          )
          {}
        end

        # The message ships as `body_html` and is delivered as such — an
        # unescaped `<` or `&` coming from a record value would break the
        # outbound message or smuggle markup into it.
        def interpolate(template, record, escape_html:)
          template.gsub(TOKEN_RE) do
            key = ::Regexp.last_match(1)
            value = record[key]
            next '' if value.nil?

            escape_html ? CGI.escapeHTML(value.to_s) : value.to_s
          end
        end

        def present?(value)
          !value.nil? && value.to_s != ''
        end
      end
    end
  end
end
