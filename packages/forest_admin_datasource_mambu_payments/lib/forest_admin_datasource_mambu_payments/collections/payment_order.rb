# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class PaymentOrder < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      client_resource :payment_order

      def initialize(datasource)
        super(datasource, 'MambuPaymentOrder')
        define_schema
        define_relations
        reconcile_filter_operators!
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

      # NOTE: server-side filters verified against Numeral's `GET /payment_orders` docs.
      # Add new entries here (status, direction, currency, created_at ranges, …) as
      # we confirm them — anything not declared raises a clear error rather than
      # silently returning unfiltered results.
      def collection_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          # Numeral's list endpoint exposes the receiving external account
          # under the `external_account_id` query param.
          'receiving_account_id' => { ops: [Operators::EQUAL, Operators::IN],
                                      param: 'external_account_id' }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'connected_account_id', relation_name: 'connected_account',
            collection: 'MambuConnectedAccount' },
          { foreign_key: 'receiving_account_id', relation_name: 'external_account',
            collection: 'MambuExternalAccount' }
        ]
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: false, is_sortable: true))
        add_field('receiving_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_DIRECTION,
                                                is_read_only: false, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', is_read_only: false, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('reference', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('purpose', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('end_to_end_id', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('idempotency_key', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('requested_execution_date', ColumnSchema.new(column_type: 'Date', is_read_only: false,
                                                               is_sortable: true))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('initiated_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: false))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('originating_account', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('receiving_account', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
