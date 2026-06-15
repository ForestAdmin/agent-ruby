module ForestAdminDatasourceMambuPayments
  module Collections
    class Transaction < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      client_resource :transaction

      def initialize(datasource)
        super(datasource, 'MambuTransaction')
        define_schema
        define_relations
        reconcile_filter_operators!
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
        add_field('category', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_DIRECTION,
                                                is_read_only: true, is_sortable: false))
        add_field('amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('description', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('structured_reference', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                           is_sortable: false))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('booking_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('internal_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: true, is_sortable: false))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: true, is_sortable: false))
        add_field('uetr', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: true))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
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
