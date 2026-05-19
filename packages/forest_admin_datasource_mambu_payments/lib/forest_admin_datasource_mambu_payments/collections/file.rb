module ForestAdminDatasourceMambuPayments
  module Collections
    class File < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION = %w[incoming outgoing].freeze
      ENUM_STATUS = %w[created approved canceled sent rejected processed received].freeze

      def initialize(datasource)
        super(datasource, 'MambuFile')
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
          'connected_account_ids' => a['connected_account_ids'],
          'direction' => a['direction'],
          'category' => a['category'],
          'format' => a['format'],
          'filename' => a['filename'],
          'size' => a['size'],
          'summary' => a['summary'],
          'status' => a['status'],
          'status_details' => a['status_details'],
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
        return ids.filter_map { |id| datasource.client.find_file(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_files(**params)
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
        # The API also returns connected_account_ids (an array) for files that
        # aggregate operations across multiple accounts; surfaced as Json since
        # Forest can't model an array of foreign keys natively.
        add_field('connected_account_ids', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                            is_read_only: true, is_sortable: false))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                enum_values: ENUM_DIRECTION,
                                                is_read_only: true, is_sortable: true))
        add_field('category', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: true, is_sortable: true))
        add_field('format', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: true))
        add_field('filename', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: true, is_sortable: true))
        add_field('size', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                           is_read_only: true, is_sortable: true))
        add_field('summary', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                              is_read_only: true, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                             enum_values: ENUM_STATUS,
                                             is_read_only: true, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: true, is_sortable: false))
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
