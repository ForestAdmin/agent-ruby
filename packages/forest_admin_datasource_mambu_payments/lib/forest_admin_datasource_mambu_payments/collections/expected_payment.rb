# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class ExpectedPayment < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      def initialize(datasource)
        super(datasource, 'MambuExpectedPayment')
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

      def create(_caller, data)
        serialize(datasource.client.create_expected_payment(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_expected_payment(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_expected_payment(id) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'connected_account_id' => a['connected_account_id'],
          'internal_account_id' => a['internal_account_id'],
          'external_account_id' => a['external_account_id'],
          'type' => a['type'],
          'direction' => a['direction'],
          'status' => a['status'],
          'amount' => a['amount'],
          'amount_min' => a['amount_min'],
          'amount_max' => a['amount_max'],
          'currency' => a['currency'],
          'reference' => a['reference'],
          'end_to_end_id' => a['end_to_end_id'],
          'expected_at' => a['expected_at'],
          'earliest_expected_at' => a['earliest_expected_at'],
          'latest_expected_at' => a['latest_expected_at'],
          'counterparty' => a['counterparty'],
          'matched_amount' => a['matched_amount'],
          'matched_payments' => a['matched_payments'],
          'custom_fields' => a['custom_fields'],
          'metadata' => a['metadata'],
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
        return ids.filter_map { |id| datasource.client.find_expected_payment(id) } if ids

        page, per_page = translate_page(filter.page)
        datasource.client.list_expected_payments(page: page, limit: per_page)
      end

      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object status created_at matched_amount matched_payments].each { |k| attrs.delete(k) }
        attrs
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
                                                           is_read_only: false, is_sortable: true))
        add_field('internal_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: false, is_sortable: false))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: false, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                enum_values: ENUM_DIRECTION,
                                                is_read_only: false, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                             is_read_only: false, is_sortable: false))
        add_field('amount_min', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                 is_read_only: false, is_sortable: false))
        add_field('amount_max', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                 is_read_only: false, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: false, is_sortable: false))
        add_field('reference', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('end_to_end_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                    is_read_only: false, is_sortable: false))
        add_field('expected_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                  is_read_only: false, is_sortable: true))
        add_field('earliest_expected_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                           is_read_only: false, is_sortable: true))
        add_field('latest_expected_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                         is_read_only: false, is_sortable: true))
        add_field('counterparty', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                   is_read_only: false, is_sortable: false))
        add_field('matched_amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                     is_read_only: true, is_sortable: false))
        add_field('matched_payments', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                       is_read_only: true, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                    is_read_only: false, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
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
