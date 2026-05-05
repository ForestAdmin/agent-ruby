module ForestAdminDatasourceZendesk
  module Schema
    # Returns entries shaped { column_name:, zendesk_id:, zendesk_key:, schema: }.
    # `zendesk_key` is set for user/org fields (Zendesk addresses those by key);
    # ticket fields use `zendesk_id` only.
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

      # Skip non-removable ticket fields: those are system fields the Ticket
      # schema already declares (subject, status, ...), and re-adding them
      # would conflict.
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
        when :ticket then ["custom_#{raw["id"]}", nil]
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
          # Forest rejects empty Enum schemas; fall back to String so the column
          # still appears.
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
