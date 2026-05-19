module ForestAdminDatasourceMambuPayments
  module Collections
    class Balance < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[debit credit].freeze

      def initialize(datasource)
        super(datasource, 'MambuBalance')
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

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'connected_account_id' => a['connected_account_id'],
          'type' => a['type'],
          'direction' => a['direction'],
          'amount' => a['amount'],
          'currency' => a['currency'],
          'date' => a['date'],
          'bank_data' => a['bank_data'],
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
        return ids.filter_map { |id| datasource.client.find_balance(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_balances(**params)
      end

      def api_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def embed_relations(rows, records, projection)
        sources = records.map { |r| attrs_of(r) }
        ca = datasource.get_collection('MambuConnectedAccount')
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'connected_account_id', relation_name: 'connected_account',
          fetcher: ->(id) { datasource.client.find_connected_account(id) },
          serializer: ->(raw) { ca.serialize(raw) }
        )
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: true, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                enum_values: ENUM_DIRECTION, is_read_only: true, is_sortable: false))
        add_field('amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: true, is_sortable: false))
        add_field('date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                           is_read_only: true, is_sortable: true))
        add_field('bank_data', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
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
