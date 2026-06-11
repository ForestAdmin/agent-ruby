# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class InternalAccount < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      client_resource :internal_account

      def initialize(datasource)
        super(datasource, 'MambuInternalAccount')
        define_schema
        define_relations
        reconcile_filter_operators!
        enable_count
      end

      def create(_caller, data)
        serialize(datasource.client.create_internal_account(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_internal_account(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_internal_account(id) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'status' => a['status'],
          'status_details' => a['status_details'],
          'type' => a['type'],
          'name' => a['name'],
          'holder_name' => a['holder_name'],
          'alternative_holder_names' => a['alternative_holder_names'],
          'connected_account_ids' => a['connected_account_ids'],
          'account_number' => a['account_number'],
          'account_number_format' => a['account_number_format'],
          'bank_code' => a['bank_code'],
          'bank_name' => a['bank_name'],
          'bank_address' => a['bank_address'],
          'bank_code_format' => a['bank_code_format'],
          'holder_address' => a['holder_address'],
          'account_holder_id' => a['account_holder_id'],
          'creditor_identifier' => a['creditor_identifier'],
          'organization_identification' => a['organization_identification'],
          'customer_bic' => a['customer_bic'],
          'distinguished_name' => a['distinguished_name'],
          'currencies' => a['currencies'],
          'cbs_source' => a['cbs_source'],
          'cbs_account_id' => a['cbs_account_id'],
          'cbs_account_type' => a['cbs_account_type'],
          'synchronized_with_bank' => a['synchronized_with_bank'],
          'metadata' => a['metadata'],
          'bank_data' => a['bank_data'],
          'custom_fields' => a['custom_fields'],
          'created_at' => a['created_at']
        }
      end

      protected

      def collection_filters
        {
          'account_holder_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'account_holder_id', relation_name: 'account_holder',
            collection: 'MambuAccountHolder' }
        ]
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: true))
        add_field('name', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: true))
        add_field('holder_name', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('alternative_holder_names', ColumnSchema.new(column_type: 'Json', is_read_only: false,
                                                               is_sortable: false))
        add_field('connected_account_ids', ColumnSchema.new(column_type: 'Json', is_read_only: false,
                                                            is_sortable: false))
        add_field('account_number', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('account_number_format', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                            is_sortable: false))
        add_field('bank_code', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('bank_name', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('bank_address', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('bank_code_format', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                       is_sortable: false))
        add_field('holder_address', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('account_holder_id', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                        is_sortable: true))
        add_field('creditor_identifier', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                          is_sortable: false))
        add_field('organization_identification', ColumnSchema.new(column_type: 'Json', is_read_only: false,
                                                                  is_sortable: false))
        add_field('customer_bic', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('distinguished_name', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                         is_sortable: false))
        add_field('currencies', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('cbs_source', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('cbs_account_id', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('cbs_account_type', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                       is_sortable: false))
        add_field('synchronized_with_bank', ColumnSchema.new(column_type: 'Boolean', is_read_only: false,
                                                             is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
      end

      def define_relations
        add_field('account_holder', ManyToOneSchema.new(
                                      foreign_collection: 'MambuAccountHolder',
                                      foreign_key: 'account_holder_id',
                                      foreign_key_target: 'id'
                                    ))
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
