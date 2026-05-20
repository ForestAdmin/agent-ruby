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

      def initialize(datasource)
        super(datasource, 'MambuReturn')
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

      def aggregate_count(caller, filter)
        list(caller, filter, ['id']).size
      end

      private

      def fetch_records(_caller, filter)
        ids = extract_id_lookup(filter.condition_tree)
        return ids.filter_map { |id| datasource.client.find_return(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_returns(**params)
      end

      def api_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'related_payment_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'status' => { ops: [Operators::EQUAL, Operators::IN] },
          'type' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      # The Numeral create payload is narrow (related_payment_id, return_reason,
      # related_payment_suspended, metadata); update is even narrower (status +
      # status_details, OR metadata). We blacklist system-managed/read-only
      # fields rather than whitelisting so a future writable field doesn't get
      # silently swallowed if we forget to update this list.
      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object connected_account_id related_payment_type return_type type direction amount
           currency reconciliation_status reconciled_amount value_date booking_date
           originating_account receiving_account aggregation_reference file_id created_at].each do |k|
          attrs.delete(k)
        end
        attrs
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
        # related_payment_id can target a payment_order OR an incoming_payment
        # depending on related_payment_type — we expose it as a plain string
        # rather than a typed relation (Forest can't model the polymorphism).
        add_field('related_payment_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                         is_read_only: false, is_sortable: false))
        add_field('related_payment_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                           enum_values: ENUM_RELATED_PAYMENT,
                                                           is_read_only: true, is_sortable: false))
        add_field('related_payment_suspended', ColumnSchema.new(column_type: 'Boolean', filter_operators: BOOL_OPS,
                                                                is_read_only: false, is_sortable: false))
        add_field('return_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                  enum_values: ENUM_RETURN_TYPE,
                                                  is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                           enum_values: ENUM_TYPE, is_read_only: true, is_sortable: true))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                enum_values: ENUM_DIRECTION, is_read_only: true, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                             enum_values: ENUM_STATUS, is_read_only: false, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: false, is_sortable: false))
        add_field('return_reason', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                    is_read_only: false, is_sortable: false))
        add_field('amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('currency', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                               is_read_only: true, is_sortable: false))
        add_field('reconciliation_status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                            is_read_only: true, is_sortable: false))
        add_field('reconciled_amount', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                        is_read_only: true, is_sortable: false))
        add_field('value_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('booking_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                   is_read_only: true, is_sortable: true))
        add_field('originating_account', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                          is_read_only: true, is_sortable: false))
        add_field('receiving_account', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                        is_read_only: true, is_sortable: false))
        add_field('aggregation_reference', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                            is_read_only: true, is_sortable: false))
        add_field('file_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                              is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
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
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
