# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class Return < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_DIRECTION       = %w[credit debit].freeze
      ENUM_TYPE            = %w[sepa sepa_instant].freeze
      ENUM_RETURN_TYPE     = %w[return refund reversal].freeze
      ENUM_STATUS          = %w[pending sent processing executed received rejected].freeze
      ENUM_RELATED_PAYMENT = %w[payment_order incoming_payment].freeze

      client_resource :return

      def initialize(datasource)
        super(datasource, 'MambuReturn')
        define_schema
        define_relations
        reconcile_filter_operators!
      end

      def create(_caller, data)
        serialize(datasource.client.create_return(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_return(id, payload) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'connected_account_id' => a['connected_account_id'],
          'related_payment_id' => a['related_payment_id'],
          'related_payment_type' => a['related_payment_type'],
          'related_payment_suspended' => a['related_payment_suspended'],
          'return_type' => a['return_type'],
          'type' => a['type'],
          'direction' => a['direction'],
          'status' => a['status'],
          'status_details' => a['status_details'],
          'return_reason' => a['return_reason'],
          'amount' => a['amount'],
          'currency' => a['currency'],
          'reconciliation_status' => a['reconciliation_status'],
          'reconciled_amount' => a['reconciled_amount'],
          'value_date' => a['value_date'],
          'booking_date' => a['booking_date'],
          'originating_account' => a['originating_account'],
          'receiving_account' => a['receiving_account'],
          'aggregation_reference' => a['aggregation_reference'],
          'file_id' => a['file_id'],
          'metadata' => a['metadata'],
          'created_at' => a['created_at']
        }
      end

      protected

      def collection_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'related_payment_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'status' => { ops: [Operators::EQUAL, Operators::IN] },
          'type' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'connected_account_id', relation_name: 'connected_account',
            collection: 'MambuConnectedAccount' }
        ]
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: true, is_sortable: true))
        # related_payment_id can target a payment_order OR an incoming_payment
        # depending on related_payment_type — we expose it as a plain string
        # rather than a typed relation (Forest can't model the polymorphism).
        add_field('related_payment_id', ColumnSchema.new(column_type: 'String',
                                                         is_read_only: false, is_sortable: false))
        add_field('related_payment_type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_RELATED_PAYMENT,
                                                           is_read_only: true, is_sortable: false))
        add_field('related_payment_suspended', ColumnSchema.new(column_type: 'Boolean',
                                                                is_read_only: false, is_sortable: false))
        add_field('return_type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_RETURN_TYPE,
                                                  is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_TYPE,
                                           is_read_only: true, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_DIRECTION,
                                                is_read_only: true, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_STATUS,
                                             is_read_only: false, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('return_reason', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: false))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: false))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('booking_date', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('originating_account', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('receiving_account', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('aggregation_reference', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                            is_sortable: false))
        add_field('file_id', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
