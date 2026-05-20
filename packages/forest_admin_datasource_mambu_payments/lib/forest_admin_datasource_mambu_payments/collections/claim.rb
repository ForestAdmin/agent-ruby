# rubocop:disable Metrics/ClassLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class Claim < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_TYPE            = %w[sepa_non_receipt sepa_value_date_correction].freeze
      ENUM_STATUS          = %w[created processing sent received accepted rejected].freeze
      ENUM_RELATED_PAYMENT = %w[payment_order incoming_payment].freeze

      def initialize(datasource)
        super(datasource, 'MambuClaim')
        define_schema
        define_relations
        enable_count
      end

      def list(caller, filter, projection)
        records = fetch_records(caller, filter)
        rows = records.map { |r| project(serialize(r), projection) }
        embed_relations(rows, records, projection)
        rows
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'type' => a['type'],
          'status' => a['status'],
          'status_details' => a['status_details'],
          'reason' => a['reason'],
          'value_date' => a['value_date'],
          'connected_account_id' => a['connected_account_id'],
          'related_payment_type' => a['related_payment_type'],
          'related_payment_id' => a['related_payment_id'],
          'related_payment' => a['related_payment'],
          'metadata' => a['metadata'],
          'bank_data' => a['bank_data'],
          'created_at' => a['created_at']
        }
      end

      protected

      def aggregate_count(caller, filter)
        list(caller, filter, ['id']).size
      end

      private

      def fetch_records(_caller, filter)
        ids = extract_id_lookup(filter.condition_tree)
        return ids.filter_map { |id| datasource.client.find_claim(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_claims(**params)
      end

      def api_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'related_payment_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'status' => { ops: [Operators::EQUAL, Operators::IN] },
          'type' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def embed_relations(rows, records, projection)
        sources = records.map { |r| attrs_of(r) }
        ca = datasource.get_collection('MambuConnectedAccount')
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'connected_account_id', relation_name: 'connected_account',
          fetcher: ->(id) { datasource.client.find_connected_account(id) },
          serializer: ->(raw) { ca.serialize(raw) }
        )
      end

      # Claims are immutable from Forest's perspective: they arrive from the
      # bank network (or the sandbox simulator) and the only way to act on
      # them is accept/reject, which belong in a smart-action plugin. We mark
      # every column read-only to match.
      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                           enum_values: ENUM_TYPE, is_read_only: true, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                             enum_values: ENUM_STATUS, is_read_only: true, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: true, is_sortable: false))
        add_field('reason', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: true, is_sortable: true))
        add_field('related_payment_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                           enum_values: ENUM_RELATED_PAYMENT,
                                                           is_read_only: true, is_sortable: false))
        # related_payment_id can target a payment_order OR an incoming_payment
        # depending on related_payment_type. Forest can't model this polymorphism
        # natively, so we expose it as a plain string column.
        add_field('related_payment_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                         is_read_only: true, is_sortable: false))
        add_field('related_payment', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                      is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: true, is_sortable: false))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
      end

      def define_relations
        add_field('connected_account', ManyToOneSchema.new(
                                         foreign_collection: 'MambuConnectedAccount',
                                         foreign_key: 'connected_account_id',
                                         foreign_key_target: 'id'
                                       ))
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
