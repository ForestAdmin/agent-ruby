# rubocop:disable Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class ConnectedAccount < BaseCollection
      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema

      client_resource :connected_account

      def initialize(datasource)
        super(datasource, 'MambuConnectedAccount')
        define_schema
        define_relations
        reconcile_filter_operators!
        enable_count
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'name' => a['name'],
          'distinguished_name' => a['distinguished_name'],
          'type' => a['type'],
          'currency' => a['currency'],
          'bank_id' => a['bank_id'],
          'bank_name' => a['bank_name'],
          'bank_code' => a['bank_code'],
          'bank_code_format' => a['bank_code_format'],
          'bank_address' => a['bank_address'],
          'account_number' => a['account_number'],
          'account_number_format' => a['account_number_format'],
          'settlement_account' => a['settlement_account'],
          'creditor_identifier' => a['creditor_identifier'],
          'legal_entity_identifier' => a['legal_entity_identifier'],
          'receiving_agent' => a['receiving_agent'],
          'services_activated' => a['services_activated'],
          'file_auto_approval' => a['file_auto_approval'],
          'return_auto_approval' => a['return_auto_approval'],
          'incoming_instant_payment_auto_approval' => a['incoming_instant_payment_auto_approval'],
          'address' => a['address'],
          'metadata' => a['metadata'],
          'bank_data' => a['bank_data'],
          'account_number_generation_settings' => a['account_number_generation_settings'],
          'disabled_at' => a['disabled_at'],
          'created_at' => a['created_at']
        }
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('name', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('distinguished_name', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                         is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('bank_id', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('bank_name', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('bank_code', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('bank_code_format', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                       is_sortable: false))
        add_field('bank_address', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('account_number', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('account_number_format', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: false))
        add_field('settlement_account', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                         is_sortable: false))
        add_field('creditor_identifier', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                          is_sortable: false))
        add_field('legal_entity_identifier', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                              is_sortable: false))
        add_field('receiving_agent', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('services_activated', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('file_auto_approval', ColumnSchema.new(column_type: 'Boolean', is_read_only: true,
                                                         is_sortable: false))
        add_field('return_auto_approval', ColumnSchema.new(column_type: 'Boolean', is_read_only: true,
                                                           is_sortable: false))
        add_field('incoming_instant_payment_auto_approval',
                  ColumnSchema.new(column_type: 'Boolean', is_read_only: true, is_sortable: false))
        add_field('address', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('account_number_generation_settings',
                  ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('disabled_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
      end

      def define_relations
        add_field('transactions', OneToManySchema.new(foreign_collection: 'MambuTransaction',
                                                      origin_key: 'connected_account_id', origin_key_target: 'id'))
        add_field('payment_orders', OneToManySchema.new(foreign_collection: 'MambuPaymentOrder',
                                                        origin_key: 'connected_account_id', origin_key_target: 'id'))
        add_field('balances', OneToManySchema.new(foreign_collection: 'MambuBalance',
                                                  origin_key: 'connected_account_id', origin_key_target: 'id'))
      end
    end
  end
end
# rubocop:enable Metrics/MethodLength
