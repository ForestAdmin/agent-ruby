# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class ConnectedAccount < BaseCollection
      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema

      def initialize(datasource)
        super(datasource, 'MambuConnectedAccount')
        define_schema
        define_relations
        enable_count
      end

      def list(caller, filter, projection)
        records = fetch_records(caller, filter)
        records.map { |r| project(serialize(r), projection) }
      end

      def create(_caller, data)
        serialize(datasource.client.create_connected_account(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_connected_account(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_connected_account(id) }
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

      protected

      def aggregate_count(caller, filter)
        list(caller, filter, ['id']).size
      end

      private

      def fetch_records(_caller, filter)
        ids = extract_id_lookup(filter.condition_tree)
        return ids.filter_map { |id| datasource.client.find_connected_account(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_connected_accounts(**params)
      end

      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object created_at disabled_at bank_data].each { |k| attrs.delete(k) }
        attrs
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('distinguished_name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                         is_read_only: false, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('currency', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: false, is_sortable: false))
        add_field('bank_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                              is_read_only: false, is_sortable: false))
        add_field('bank_name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('bank_code', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('bank_code_format', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                       is_read_only: false, is_sortable: false))
        add_field('bank_address', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                   is_read_only: false, is_sortable: false))
        add_field('account_number', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: false, is_sortable: false))
        add_field('account_number_format', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                            is_read_only: false, is_sortable: false))
        add_field('settlement_account', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                         is_read_only: false, is_sortable: false))
        add_field('creditor_identifier', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: false, is_sortable: false))
        add_field('legal_entity_identifier', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                              is_read_only: false, is_sortable: false))
        add_field('receiving_agent', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                      is_read_only: false, is_sortable: false))
        add_field('services_activated', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                         is_read_only: false, is_sortable: false))
        add_field('file_auto_approval', ColumnSchema.new(column_type: 'Boolean', filter_operators: BOOL_OPS,
                                                         is_read_only: false, is_sortable: false))
        add_field('return_auto_approval', ColumnSchema.new(column_type: 'Boolean', filter_operators: BOOL_OPS,
                                                           is_read_only: false, is_sortable: false))
        add_field('incoming_instant_payment_auto_approval',
                  ColumnSchema.new(column_type: 'Boolean', filter_operators: BOOL_OPS,
                                   is_read_only: false, is_sortable: false))
        add_field('address', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                              is_read_only: false, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                is_read_only: true, is_sortable: false))
        add_field('account_number_generation_settings',
                  ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                   is_read_only: false, is_sortable: false))
        add_field('disabled_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                  is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
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
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
