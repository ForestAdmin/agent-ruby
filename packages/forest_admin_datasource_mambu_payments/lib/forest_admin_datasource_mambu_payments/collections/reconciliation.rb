module ForestAdminDatasourceMambuPayments
  module Collections
    class Reconciliation < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_MATCH_TYPE   = %w[manual auto].freeze
      ENUM_PAYMENT_TYPE = %w[payment_order incoming_payment return expected_payment payment_capture].freeze

      client_resource :reconciliation

      def initialize(datasource)
        super(datasource, 'MambuReconciliation')
        define_schema
        define_relations
        reconcile_filter_operators!
        enable_count
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

      def collection_filters
        {
          'transaction_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'payment_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'payment_type' => { ops: [Operators::EQUAL, Operators::IN] },
          'match_type' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'transaction_id', relation_name: 'transaction', collection: 'MambuTransaction' }
        ]
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        # transaction_id is set on create and never mutated afterwards — Numeral
        # rejects PATCH on anything besides metadata.
        add_field('transaction_id', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: true))
        # payment_id is polymorphic in Numeral (payment_order / incoming_payment /
        # return / expected_payment / payment_capture, discriminated by
        # payment_type). Forest can't model that natively, so we expose it as
        # a plain string column rather than a typed ManyToOne.
        add_field('payment_id', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('payment_type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_PAYMENT_TYPE,
                                                   is_read_only: true, is_sortable: true))
        add_field('amount', ColumnSchema.new(column_type: 'Number', is_read_only: false, is_sortable: false))
        add_field('match_type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_MATCH_TYPE,
                                                 is_read_only: true, is_sortable: true))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('canceled_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
