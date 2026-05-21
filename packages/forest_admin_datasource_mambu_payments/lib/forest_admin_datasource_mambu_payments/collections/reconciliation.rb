# rubocop:disable Metrics/ClassLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class Reconciliation < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_MATCH_TYPE   = %w[manual auto].freeze
      ENUM_PAYMENT_TYPE = %w[payment_order incoming_payment return expected_payment payment_capture].freeze

      def initialize(datasource)
        super(datasource, 'MambuReconciliation')
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
        serialize(datasource.client.create_reconciliation(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_reconciliation(id, payload) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'transaction_id' => a['transaction_id'],
          'payment_id' => a['payment_id'],
          'payment_type' => a['payment_type'],
          'amount' => a['amount'],
          'match_type' => a['match_type'],
          'metadata' => a['metadata'],
          'canceled_at' => a['canceled_at'],
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
        return ids.filter_map { |id| datasource.client.find_reconciliation(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_reconciliations(**params)
      end

      def api_filters
        {
          'transaction_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'payment_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'payment_type' => { ops: [Operators::EQUAL, Operators::IN] },
          'match_type' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      # Numeral's create payload is narrow (transaction_id required, payment_id /
      # amount / metadata optional). Update only accepts metadata. We blacklist
      # the system-managed fields so the same helper can serve both calls.
      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object match_type canceled_at created_at].each { |k| attrs.delete(k) }
        attrs
      end

      def embed_relations(rows, records, projection)
        sources = records.map { |r| attrs_of(r) }
        tx = datasource.get_collection('MambuTransaction')
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'transaction_id', relation_name: 'transaction',
          fetcher: ->(id) { datasource.client.find_transaction(id) },
          serializer: ->(raw) { tx.serialize(raw) }
        )
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        # transaction_id is set on create and never mutated afterwards — Numeral
        # rejects PATCH on anything besides metadata.
        add_field('transaction_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: false, is_sortable: true))
        # payment_id is polymorphic in Numeral (payment_order / incoming_payment /
        # return / expected_payment / payment_capture, discriminated by
        # payment_type). Forest can't model that natively, so we expose it as
        # a plain string column rather than a typed ManyToOne.
        add_field('payment_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                 is_read_only: false, is_sortable: false))
        add_field('payment_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                   enum_values: ENUM_PAYMENT_TYPE,
                                                   is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                             is_read_only: false, is_sortable: false))
        add_field('match_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                 enum_values: ENUM_MATCH_TYPE,
                                                 is_read_only: true, is_sortable: true))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
        add_field('canceled_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                  is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
      end

      def define_relations
        add_field('transaction', ManyToOneSchema.new(
                                   foreign_collection: 'MambuTransaction',
                                   foreign_key: 'transaction_id',
                                   foreign_key_target: 'id'
                                 ))
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
