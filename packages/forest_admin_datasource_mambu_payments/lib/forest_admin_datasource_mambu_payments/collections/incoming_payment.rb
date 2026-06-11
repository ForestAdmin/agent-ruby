# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class IncomingPayment < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      client_resource :incoming_payment

      def initialize(datasource)
        super(datasource, 'MambuIncomingPayment')
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
          'connected_account_id' => a['connected_account_id'],
          'type' => a['type'],
          'status' => a['status'],
          'amount' => a['amount'],
          'currency' => a['currency'],
          'end_to_end_id' => a['end_to_end_id'],
          'uetr' => a['uetr'],
          'reference' => a['reference'],
          'structured_reference' => a['structured_reference'],
          'value_date' => a['value_date'],
          'booking_date' => a['booking_date'],
          'originating_account' => a['originating_account'],
          'receiving_account' => a['receiving_account'],
          'internal_account_id' => a['internal_account_id'],
          'external_account_id' => a['external_account_id'],
          'reconciliation_status' => a['reconciliation_status'],
          'reconciled_amount' => a['reconciled_amount'],
          'return_information' => a['return_information'],
          'custom_fields' => a['custom_fields'],
          'metadata' => a['metadata'],
          'created_at' => a['created_at']
        }
      end

      protected

      def collection_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'internal_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'external_account_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'connected_account_id', relation_name: 'connected_account',
            collection: 'MambuConnectedAccount' },
          { foreign_key: 'internal_account_id', relation_name: 'internal_account',
            collection: 'MambuInternalAccount' },
          { foreign_key: 'external_account_id', relation_name: 'external_account',
            collection: 'MambuExternalAccount' }
        ]
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('end_to_end_id', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('uetr', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('reference', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('structured_reference', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: true, is_sortable: false))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('booking_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('originating_account', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('receiving_account', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('internal_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: true, is_sortable: false))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: true, is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String',
                                                            is_read_only: true, is_sortable: true))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('return_information', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
