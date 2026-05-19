module ForestAdminDatasourceMambuPayments
  module Collections
    class AccountHolder < BaseCollection
      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema

      def initialize(datasource)
        super(datasource, 'MambuAccountHolder')
        define_schema
        define_relations
        enable_count
      end

      def list(caller, filter, projection)
        records = fetch_records(caller, filter)
        records.map { |r| project(serialize(r), projection) }
      end

      def create(_caller, data)
        serialize(datasource.client.create_account_holder(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_account_holder(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_account_holder(id) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'name' => a['name'],
          'metadata' => a['metadata'],
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
        return ids.filter_map { |id| datasource.client.find_account_holder(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_account_holders(**params)
      end

      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object created_at disabled_at].each { |k| attrs.delete(k) }
        attrs
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
        add_field('disabled_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                  is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
      end

      def define_relations
        add_field('external_accounts', OneToManySchema.new(
                                         foreign_collection: 'MambuExternalAccount',
                                         origin_key: 'account_holder_id', origin_key_target: 'id'
                                       ))
        add_field('internal_accounts', OneToManySchema.new(
                                         foreign_collection: 'MambuInternalAccount',
                                         origin_key: 'account_holder_id', origin_key_target: 'id'
                                       ))
      end
    end
  end
end
