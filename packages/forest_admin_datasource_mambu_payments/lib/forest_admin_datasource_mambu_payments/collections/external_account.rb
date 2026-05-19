# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class ExternalAccount < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      def initialize(datasource)
        super(datasource, 'MambuExternalAccount')
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
        serialize(datasource.client.create_external_account(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_external_account(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_external_account(id) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'type' => a['type'],
          'status' => a['status'],
          'status_details' => a['status_details'],
          'name' => a['name'],
          'holder_name' => a['holder_name'],
          'holder_address' => a['holder_address'],
          'account_number' => a['account_number'],
          'account_number_format' => a['account_number_format'],
          'bank_code' => a['bank_code'],
          'bank_name' => a['bank_name'],
          'bank_address' => a['bank_address'],
          'bank_code_format' => a['bank_code_format'],
          'account_holder_id' => a['account_holder_id'],
          'organization_identification' => a['organization_identification'],
          'company_registration_number' => a['company_registration_number'],
          'company_registration_number_type' => a['company_registration_number_type'],
          'metadata' => a['metadata'],
          'custom_fields' => a['custom_fields'],
          'account_verification' => a['account_verification'],
          'idempotency_key' => a['idempotency_key'],
          'created_at' => a['created_at'],
          'disabled_at' => a['disabled_at']
        }
      end

      protected

      def aggregate_count(caller, filter)
        list(caller, filter, ['id']).size
      end

      private

      def fetch_records(_caller, filter)
        ids = extract_id_lookup(filter.condition_tree)
        return ids.filter_map { |id| datasource.client.find_external_account(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_external_accounts(**params)
      end

      def api_filters
        {
          'account_holder_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object status status_details created_at disabled_at account_verification].each { |k| attrs.delete(k) }
        attrs
      end

      def embed_relations(rows, records, projection)
        sources = records.map { |r| attrs_of(r) }
        ah = datasource.get_collection('MambuAccountHolder')
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'account_holder_id', relation_name: 'account_holder',
          fetcher: ->(id) { datasource.client.find_account_holder(id) },
          serializer: ->(raw) { ah.serialize(raw) }
        )
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: true, is_sortable: false))
        add_field('name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('holder_name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                  is_read_only: false, is_sortable: false))
        add_field('holder_address', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                     is_read_only: false, is_sortable: false))
        add_field('account_number', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: false, is_sortable: false))
        add_field('account_number_format', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                            is_read_only: false, is_sortable: false))
        add_field('bank_code', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('bank_name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('bank_address', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                   is_read_only: false, is_sortable: false))
        add_field('bank_code_format', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                       is_read_only: false, is_sortable: false))
        add_field('account_holder_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                        is_read_only: false, is_sortable: true))
        add_field('organization_identification', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                                  is_read_only: false, is_sortable: false))
        add_field('company_registration_number', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                                  is_read_only: false, is_sortable: false))
        add_field('company_registration_number_type',
                  ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                   is_read_only: false, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                    is_read_only: false, is_sortable: false))
        add_field('account_verification', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                           is_read_only: true, is_sortable: false))
        add_field('idempotency_key', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                      is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('disabled_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                  is_read_only: true, is_sortable: true))
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
