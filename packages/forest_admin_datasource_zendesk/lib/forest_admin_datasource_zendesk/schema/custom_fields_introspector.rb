module ForestAdminDatasourceZendesk
  module Schema
    # Discovers admin-defined Zendesk custom fields and produces
    # ColumnSchema entries our collections can `add_field` directly.
    #
    # Each entry has the shape:
    #   { column_name: 'custom_360001234', zendesk_id: 360001234,
    #     zendesk_key: nil, schema: ColumnSchema }
    #
    # `zendesk_key` is set for user_fields/organization_fields (Zendesk
    # exposes those keyed). `zendesk_id` is set for ticket_fields.
    class CustomFieldsIntrospector
      ColumnSchema = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

      STRING_OPS = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                    Operators::PRESENT, Operators::BLANK].freeze
      NUMBER_OPS = (STRING_OPS + [Operators::GREATER_THAN, Operators::LESS_THAN]).freeze
      DATE_OPS   = [Operators::EQUAL, Operators::BEFORE, Operators::AFTER,
                    Operators::PRESENT, Operators::BLANK].freeze

      ZENDESK_TO_COLUMN_TYPE = {
        'text' => 'String',
        'textarea' => 'String',
        'regexp' => 'String',
        'partialcreditcard' => 'String',
        'integer' => 'Number',
        'decimal' => 'Number',
        'date' => 'Dateonly',
        'checkbox' => 'Boolean',
        'dropdown' => 'Enum',
        'tagger' => 'Enum',
        'multiselect' => 'Json',
        'lookup' => 'Number'
      }.freeze

      def initialize(client)
        @client = client
      end

      def ticket_custom_fields
        introspect(@client.fetch_ticket_fields, key_strategy: :ticket)
      end

      def user_custom_fields
        introspect(@client.fetch_user_fields, key_strategy: :user_or_org)
      end

      def organization_custom_fields
        introspect(@client.fetch_organization_fields, key_strategy: :user_or_org)
      end

      private

      def introspect(raw_fields, key_strategy:)
        Array(raw_fields)
          .select { |raw| usable_field?(raw, key_strategy) }
          .filter_map { |raw| build_entry(raw, key_strategy) }
      end

      # System ticket fields can't be removed; skip them so we don't double-up
      # the columns the Ticket schema already declares (e.g. subject/status).
      # Inactive fields and unrecognized types are also skipped.
      def usable_field?(raw, key_strategy)
        return false unless raw['active']
        return false if key_strategy == :ticket && raw['removable'] == false

        ZENDESK_TO_COLUMN_TYPE.key?(raw['type'])
      end

      def build_entry(raw, key_strategy)
        column_type = ZENDESK_TO_COLUMN_TYPE.fetch(raw['type'])
        name, key   = column_naming(raw, key_strategy)
        { column_name: name, zendesk_id: raw['id'], zendesk_key: key,
          schema: build_schema(raw, column_type) }
      end

      def column_naming(raw, strategy)
        case strategy
        when :ticket
          # No reliable key on ticket_fields; use the id.
          ["custom_#{raw["id"]}", nil]
        when :user_or_org
          key = raw['key'] || "custom_#{raw["id"]}"
          [key, key]
        end
      end

      def build_schema(raw, column_type)
        opts = {
          column_type: column_type,
          filter_operators: filter_operators_for(column_type),
          is_read_only: false,
          is_sortable: false
        }

        if column_type == 'Enum'
          opts[:enum_values] = Array(raw['custom_field_options']).filter_map { |o| o['value'] }
          # If for some reason there are no options, drop back to String so the
          # column still appears (Forest rejects empty Enum schemas).
          if opts[:enum_values].empty?
            opts[:column_type] = 'String'
            opts[:filter_operators] = STRING_OPS
            opts.delete(:enum_values)
          end
        end

        ColumnSchema.new(**opts)
      end

      def filter_operators_for(column_type)
        case column_type
        when 'Number' then NUMBER_OPS
        when 'Dateonly' then DATE_OPS
        when 'Boolean' then [Operators::EQUAL, Operators::NOT_EQUAL]
        when 'Json'    then []
        else                STRING_OPS
        end
      end
    end
  end
end
