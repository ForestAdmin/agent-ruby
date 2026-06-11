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

      client_resource :event

      def initialize(datasource)
        super(datasource, 'MambuEvent')
        define_schema
        define_relations
        reconcile_filter_operators!
        enable_count
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

      # Numeral's `GET /events` exposes filtering on the polymorphic target id.
      # Used by OneToMany relations declared on PaymentOrder/IncomingPayment/etc
      # to navigate "events of this resource". `related_object_type` filtering
      # is left out because we translate the enum to Forest collection names at
      # serialize time — uniqueness of UUIDs makes the type filter redundant
      # when filtering by id anyway.
      def collection_filters
        {
          'related_object_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      # PolymorphicManyToOne is not resolved by the customizer, so we populate
      # `related_object` here when the projection requests it. Ids are grouped by
      # their (translated) related_object_type so each target collection is hit
      # with a single batched fetch_by_ids pass.
      def embed_relations(rows, records, projection)
        return if projection.nil? || !relations_in(projection).include?('related_object')

        sources = records.map { |r| attrs_of(r) }
        caches = build_related_object_caches(sources)

        rows.each_with_index do |row, i|
          src = sources[i]
          type = TYPE_TO_COLLECTION[src['related_object_type']]
          id = src['related_object_id']
          next if type.nil? || id.to_s.empty?

          row['related_object'] = caches.dig(type, id)
        end
      end

      private

      def build_related_object_caches(sources)
        ids_by_collection = Hash.new { |hash, key| hash[key] = [] }
        sources.each do |src|
          type = TYPE_TO_COLLECTION[src['related_object_type']]
          id = src['related_object_id']
          next if type.nil? || id.to_s.empty?

          ids_by_collection[type] << id
        end

        ids_by_collection.to_h do |collection_name, ids|
          target = datasource.get_collection(collection_name)
          by_id = target.send(:fetch_by_ids, ids).to_h do |raw|
            [attrs_of(raw)['id'], target.serialize(raw)]
          end
          [collection_name, by_id]
        end
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('topic', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('type', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('related_object_id', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                        is_sortable: false))
        add_field('related_object_type', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                          is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_STATUS,
                                             is_read_only: true, is_sortable: true))
        add_field('status_details', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('webhook_id', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('data', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
