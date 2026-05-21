# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class PaymentOrder < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      def initialize(datasource)
        super(datasource, 'MambuPaymentOrder')
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
        serialize(datasource.client.create_payment_order(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_payment_order(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_payment_order(id) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'connected_account_id' => a['connected_account_id'],
          'receiving_account_id' => a['receiving_account_id'],
          'type' => a['type'],
          'direction' => a['direction'],
          'status' => a['status'],
          'amount' => a['amount'],
          'currency' => a['currency'],
          'reference' => a['reference'],
          'purpose' => a['purpose'],
          'end_to_end_id' => a['end_to_end_id'],
          'idempotency_key' => a['idempotency_key'],
          'requested_execution_date' => a['requested_execution_date'],
          'value_date' => a['value_date'],
          'initiated_at' => a['initiated_at'],
          'reconciliation_status' => a['reconciliation_status'],
          'reconciled_amount' => a['reconciled_amount'],
          'originating_account' => a['originating_account'],
          'receiving_account' => a['receiving_account'],
          'metadata' => a['metadata'],
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
        return ids.filter_map { |id| datasource.client.find_payment_order(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_payment_orders(**params)
      end

      # NOTE: server-side filters verified against Numeral's `GET /payment_orders` docs.
      # Add new entries here (status, direction, currency, created_at ranges, …) as
      # we confirm them — anything not declared raises a clear error rather than
      # silently returning unfiltered results.
      def api_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          # Numeral's list endpoint exposes the receiving external account
          # under the `external_account_id` query param.
          'receiving_account_id' => { ops: [Operators::EQUAL, Operators::IN],
                                      param: 'external_account_id' }
        }
      end

      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id status created_at value_date initiated_at reconciliation_status reconciled_amount
           receiving_account_id].each do |k|
          attrs.delete(k)
        end
        attrs
      end

      def embed_relations(rows, records, projection)
        ca = datasource.get_collection('MambuConnectedAccount')
        ea = datasource.get_collection('MambuExternalAccount')
        sources = records.map { |r| attrs_of(r) }
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'connected_account_id', relation_name: 'connected_account',
          fetcher: ->(id) { datasource.client.find_connected_account(id) },
          serializer: ->(raw) { ca.serialize(raw) }
        )
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'receiving_account_id', relation_name: 'external_account',
          fetcher: ->(id) { datasource.client.find_external_account(id) },
          serializer: ->(raw) { ea.serialize(raw) }
        )
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: false, is_sortable: true))
        add_field('receiving_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                enum_values: ENUM_DIRECTION, is_read_only: false, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                             is_read_only: false, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: false, is_sortable: false))
        add_field('reference', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('purpose', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                              is_read_only: false, is_sortable: false))
        add_field('end_to_end_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                    is_read_only: false, is_sortable: false))
        add_field('idempotency_key', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                      is_read_only: false, is_sortable: false))
        add_field('requested_execution_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                               is_read_only: false, is_sortable: true))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('initiated_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                   is_read_only: true, is_sortable: true))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                            is_read_only: true, is_sortable: false))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                        is_read_only: true, is_sortable: false))
        add_field('originating_account', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                          is_read_only: true, is_sortable: false))
        add_field('receiving_account', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                        is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', filter_operators: [],
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
        add_field('external_account', ManyToOneSchema.new(
                                        foreign_collection: 'MambuExternalAccount',
                                        foreign_key: 'receiving_account_id',
                                        foreign_key_target: 'id'
                                      ))
      end
    end
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
