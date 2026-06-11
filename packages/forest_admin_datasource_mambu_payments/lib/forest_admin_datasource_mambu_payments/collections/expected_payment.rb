# rubocop:disable Metrics/ClassLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class ExpectedPayment < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      client_resource :expected_payment

      def initialize(datasource)
        super(datasource, 'MambuExpectedPayment')
        define_schema
        define_relations
        reconcile_filter_operators!
        enable_count
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
          'idempotency_key' => a['idempotency_key'],
          'connected_account_id' => a['connected_account_id'],
          'internal_account_id' => a['internal_account_id'],
          'external_account_id' => a['external_account_id'],
          'direction' => a['direction'],
          'amount_from' => a['amount_from'],
          'amount_to' => a['amount_to'],
          'currency' => a['currency'],
          'start_date' => a['start_date'],
          'end_date' => a['end_date'],
          'descriptions' => a['descriptions'],
          'reconciliation_status' => a['reconciliation_status'],
          'reconciled_amount' => a['reconciled_amount'],
          'custom_fields' => a['custom_fields'],
          'metadata' => a['metadata'],
          'created_at' => a['created_at'],
          'updated_at' => a['updated_at'],
          'canceled_at' => a['canceled_at']
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

      # The full account records are exposed through the ManyToOne relations
      # below rather than as embedded snapshot columns, so a single source of
      # truth backs both (mirrors the Transaction collection).
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
        add_field('idempotency_key', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: false, is_sortable: true))
        add_field('internal_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: false, is_sortable: false))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: false, is_sortable: false))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_DIRECTION,
                                                is_read_only: false, is_sortable: true))
        add_field('amount_from', ColumnSchema.new(column_type: 'Number', is_read_only: false, is_sortable: false))
        add_field('amount_to', ColumnSchema.new(column_type: 'Number', is_read_only: false, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('start_date', ColumnSchema.new(column_type: 'Date', is_read_only: false, is_sortable: true))
        add_field('end_date', ColumnSchema.new(column_type: 'Date', is_read_only: false, is_sortable: true))
        add_field('descriptions', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: true))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('updated_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('canceled_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
# rubocop:enable Metrics/ClassLength
