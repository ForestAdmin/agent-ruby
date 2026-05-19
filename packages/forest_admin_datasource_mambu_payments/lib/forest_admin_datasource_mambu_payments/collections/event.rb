# rubocop:disable Metrics/ClassLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class Event < BaseCollection
      PolymorphicManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema

      # Maps Numeral's `topic` / `related_object_type` enum values to Forest collection
      # names. The polymorphic relation resolver expects the type column to hold the
      # target collection name, so we translate at serialize time.
      TYPE_TO_COLLECTION = {
        'payment_order' => 'MambuPaymentOrder',
        'transaction' => 'MambuTransaction',
        'incoming_payment' => 'MambuIncomingPayment',
        'expected_payment' => 'MambuExpectedPayment',
        'direct_debit_mandate' => 'MambuDirectDebitMandate',
        'balance' => 'MambuBalance',
        'connected_account' => 'MambuConnectedAccount',
        'account_holder' => 'MambuAccountHolder',
        'internal_account' => 'MambuInternalAccount',
        'external_account' => 'MambuExternalAccount'
      }.freeze

      ENUM_STATUS = %w[created delivered pending_retry failed archived].freeze

      FETCHERS = {
        'MambuPaymentOrder' => :find_payment_order,
        'MambuTransaction' => :find_transaction,
        'MambuIncomingPayment' => :find_incoming_payment,
        'MambuExpectedPayment' => :find_expected_payment,
        'MambuDirectDebitMandate' => :find_direct_debit_mandate,
        'MambuBalance' => :find_balance,
        'MambuConnectedAccount' => :find_connected_account,
        'MambuAccountHolder' => :find_account_holder,
        'MambuInternalAccount' => :find_internal_account,
        'MambuExternalAccount' => :find_external_account
      }.freeze

      def initialize(datasource)
        super(datasource, 'MambuEvent')
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
          'topic' => a['topic'],
          'type' => a['type'],
          'related_object_id' => a['related_object_id'],
          'related_object_type' => TYPE_TO_COLLECTION[a['related_object_type']] || a['related_object_type'],
          'status' => a['status'],
          'status_details' => a['status_details'],
          'webhook_id' => a['webhook_id'],
          'data' => a['data'],
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
        return ids.filter_map { |id| datasource.client.find_event(id) } if ids

        page, per_page = translate_page(filter.page)
        params = translate_filters(filter.condition_tree).merge(page: page, limit: per_page)
        datasource.client.list_events(**params)
      end

      # PolymorphicManyToOne is not resolved by the customizer, so we populate
      # `related_object` here when the projection requests it. Records are grouped
      # by their (translated) related_object_type so each target collection is
      # queried in a single batched pass.
      def embed_relations(rows, records, projection)
        return if projection.nil? || !relations_in(projection).include?('related_object')

        sources = records.map { |r| attrs_of(r) }
        grouped = group_by_collection(sources)

        caches = grouped.transform_values do |entries|
          collection_name = entries.first[:collection_name]
          fetcher = FETCHERS[collection_name]
          serializer = datasource.get_collection(collection_name)
          ids = entries.map { |e| e[:id] }.uniq
          ids.to_h { |id| [id, datasource.client.public_send(fetcher, id)] }
             .compact
             .transform_values { |raw| serializer.serialize(raw) }
        end

        rows.each_with_index do |row, i|
          src = sources[i]
          type = TYPE_TO_COLLECTION[src['related_object_type']]
          id = src['related_object_id']
          next if type.nil? || id.nil? || id.to_s.empty?

          row['related_object'] = caches.dig(type, id)
        end
      end

      def group_by_collection(sources)
        sources.each_with_object({}) do |src, acc|
          type = TYPE_TO_COLLECTION[src['related_object_type']]
          id = src['related_object_id']
          next if type.nil? || id.nil? || id.to_s.empty?

          (acc[type] ||= []) << { collection_name: type, id: id }
        end
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('topic', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                            is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: true, is_sortable: true))
        add_field('related_object_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                        is_read_only: true, is_sortable: false))
        add_field('related_object_type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: true, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                             enum_values: ENUM_STATUS,
                                             is_read_only: true, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                     is_read_only: true, is_sortable: false))
        add_field('webhook_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                 is_read_only: true, is_sortable: false))
        add_field('data', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                           is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
      end

      def define_relations
        add_field('related_object', PolymorphicManyToOneSchema.new(
                                      foreign_key: 'related_object_id',
                                      foreign_key_type_field: 'related_object_type',
                                      foreign_collections: TYPE_TO_COLLECTION.values,
                                      foreign_key_targets: TYPE_TO_COLLECTION.values.to_h { |n| [n, 'id'] }
                                    ))
      end
    end
  end
end

# rubocop:enable Metrics/ClassLength
