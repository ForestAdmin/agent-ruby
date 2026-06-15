# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class PaymentCapture < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_TYPE                  = %w[charge chargeback refund].freeze
      ENUM_SOURCE                = %w[api reporting_file].freeze
      ENUM_RECONCILIATION_STATUS = %w[unreconciled reconciled partially_reconciled].freeze

      client_resource :payment_capture

      def initialize(datasource)
        super(datasource, 'MambuPaymentCapture')
        define_schema
        define_relations
        reconcile_filter_operators!
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'idempotency_key' => a['idempotency_key'],
          'connected_account_id' => a['connected_account_id'],
          'type' => a['type'],
          'source' => a['source'],
          'amount' => a['amount'],
          'original_payment_amount' => a['original_payment_amount'],
          'currency' => a['currency'],
          'date' => a['date'],
          'value_date' => a['value_date'],
          'remittance_date' => a['remittance_date'],
          'remittance_reference' => a['remittance_reference'],
          'transaction_reference' => a['transaction_reference'],
          'authorization_id' => a['authorization_id'],
          'payment_reference' => a['payment_reference'],
          'network' => a['network'],
          'merchant_id' => a['merchant_id'],
          'fee_amount' => a['fee_amount'],
          'fee_amount_currency' => a['fee_amount_currency'],
          'net_amount' => a['net_amount'],
          'net_amount_currency' => a['net_amount_currency'],
          'reconciliation_status' => a['reconciliation_status'],
          'reconciled_amount' => a['reconciled_amount'],
          'cbs_data' => a['cbs_data'],
          'lending' => a['lending'],
          'metadata' => a['metadata'],
          'canceled_at' => a['canceled_at'],
          'updated_at' => a['updated_at'],
          'created_at' => a['created_at']
        }
      end

      protected

      def collection_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'type' => { ops: [Operators::EQUAL, Operators::IN] },
          'source' => { ops: [Operators::EQUAL, Operators::IN] },
          'reconciliation_status' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'connected_account_id', relation_name: 'connected_account',
            collection: 'MambuConnectedAccount' }
        ]
      end

      private

      # Payment captures are emitted by PSPs (or registered manually via API
      # to reconcile reporting files). From Forest's perspective they're
      # read-only: create / update / cancel exist on the Numeral API but are
      # lifecycle operations better expressed as smart-action plugins later
      # (same approach as payment_orders' approve/cancel).
      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('idempotency_key', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_TYPE,
                                           is_read_only: true, is_sortable: true))
        add_field('source', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_SOURCE,
                                             is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('original_payment_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true,
                                                              is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('remittance_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('remittance_reference', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                           is_sortable: false))
        add_field('transaction_reference', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: false))
        add_field('authorization_id', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('payment_reference', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                        is_sortable: false))
        add_field('network', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('merchant_id', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('fee_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('fee_amount_currency', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                          is_sortable: false))
        add_field('net_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('net_amount_currency', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                          is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'Enum',
                                                            enum_values: ENUM_RECONCILIATION_STATUS,
                                                            is_read_only: true, is_sortable: true))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('cbs_data', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('lending', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('canceled_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('updated_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
