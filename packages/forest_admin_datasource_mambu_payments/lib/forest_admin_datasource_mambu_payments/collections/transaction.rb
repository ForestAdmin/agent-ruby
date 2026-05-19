# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class Transaction < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      def initialize(datasource)
        super(datasource, 'MambuTransaction')
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
          'connected_account_id' => a['connected_account_id'],
          'category' => a['category'],
          'direction' => a['direction'],
          'amount' => a['amount'],
          'currency' => a['currency'],
          'description' => a['description'],
          'structured_reference' => a['structured_reference'],
          'value_date' => a['value_date'],
          'booking_date' => a['booking_date'],
          'internal_account_snapshot' => a['internal_account'],
          'external_account_snapshot' => a['external_account'],
          'internal_account_id' => a['internal_account_id'],
          'external_account_id' => a['external_account_id'],
          'uetr' => a['uetr'],
          'bank_data' => a['bank_data'],
          'reconciliation_status' => a['reconciliation_status'],
          'reconciled_amount' => a['reconciled_amount'],
          'custom_fields' => a['custom_fields'],
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
        return ids.filter_map { |id| datasource.client.find_transaction(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_transactions(**params)
      end

      def api_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'internal_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'external_account_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def embed_relations(rows, records, projection)
        sources = records.map { |r| attrs_of(r) }
        ca = datasource.get_collection('MambuConnectedAccount')
        ia = datasource.get_collection('MambuInternalAccount')
        ea = datasource.get_collection('MambuExternalAccount')
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'connected_account_id', relation_name: 'connected_account',
          fetcher: ->(id) { datasource.client.find_connected_account(id) },
          serializer: ->(raw) { ca.serialize(raw) }
        )
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'internal_account_id', relation_name: 'internal_account',
          fetcher: ->(id) { datasource.client.find_internal_account(id) },
          serializer: ->(raw) { ia.serialize(raw) }
        )
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'external_account_id', relation_name: 'external_account',
          fetcher: ->(id) { datasource.client.find_external_account(id) },
          serializer: ->(raw) { ea.serialize(raw) }
        )
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: true, is_sortable: true))
        add_field('category', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: true, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                enum_values: ENUM_DIRECTION, is_read_only: true, is_sortable: false))
        add_field('amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: true, is_sortable: false))
        add_field('description', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                  is_read_only: true, is_sortable: false))
        add_field('structured_reference', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: true, is_sortable: false))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('booking_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                   is_read_only: true, is_sortable: true))
        add_field('internal_account_snapshot', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                                is_read_only: true, is_sortable: false))
        add_field('external_account_snapshot', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                                is_read_only: true, is_sortable: false))
        add_field('internal_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: true, is_sortable: false))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: true, is_sortable: false))
        add_field('uetr', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: true, is_sortable: false))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                is_read_only: true, is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                            is_read_only: true, is_sortable: true))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                        is_read_only: true, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', filter_operators: [],
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
        add_field('internal_account', ManyToOneSchema.new(
                                        foreign_collection: 'MambuInternalAccount',
                                        foreign_key: 'internal_account_id',
                                        foreign_key_target: 'id'
                                      ))
        add_field('external_account', ManyToOneSchema.new(
                                        foreign_collection: 'MambuExternalAccount',
                                        foreign_key: 'external_account_id',
                                        foreign_key_target: 'id'
                                      ))
      end
    end
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
