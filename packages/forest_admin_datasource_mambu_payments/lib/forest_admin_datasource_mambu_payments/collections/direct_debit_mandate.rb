# rubocop:disable Metrics/ClassLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class DirectDebitMandate < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_SEQUENCE_TYPE = %w[one_off recurrent first final].freeze
      ENUM_SCHEME = %w[sepa bacs ach].freeze

      def initialize(datasource)
        super(datasource, 'MambuDirectDebitMandate')
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
        serialize(datasource.client.create_direct_debit_mandate(build_payload(data)))
      end

      def update(caller, filter, patch)
        payload = build_payload(patch)
        ids_for(caller, filter).each { |id| datasource.client.update_direct_debit_mandate(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_direct_debit_mandate(id) }
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'connected_account_id' => a['connected_account_id'],
          'external_account_id' => a['external_account_id'],
          'type' => a['type'],
          'scheme' => a['scheme'],
          'status' => a['status'],
          'sequence_type' => a['sequence_type'],
          'reference' => a['reference'],
          'unique_mandate_reference' => a['unique_mandate_reference'],
          'creditor_identifier' => a['creditor_identifier'],
          'signature_date' => a['signature_date'],
          'signature_location' => a['signature_location'],
          'creditor' => a['creditor'],
          'debtor' => a['debtor'],
          'debtor_account' => a['debtor_account'],
          'amendment_information' => a['amendment_information'],
          'custom_fields' => a['custom_fields'],
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
        return ids.filter_map { |id| datasource.client.find_direct_debit_mandate(id) } if ids

        page, per_page = translate_page(filter.page)
        datasource.client.list_direct_debit_mandates(page: page, limit: per_page)
      end

      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        %w[id object status created_at].each { |k| attrs.delete(k) }
        attrs
      end

      def embed_relations(rows, records, projection)
        sources = records.map { |r| attrs_of(r) }
        ca = datasource.get_collection('MambuConnectedAccount')
        ea = datasource.get_collection('MambuExternalAccount')
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'connected_account_id', relation_name: 'connected_account',
          fetcher: ->(id) { datasource.client.find_connected_account(id) },
          serializer: ->(raw) { ca.serialize(raw) }
        )
        embed_many_to_one(
          rows, sources, projection,
          foreign_key: 'external_account_id', relation_name: 'external_account',
          fetcher: ->(id) { datasource.client.find_external_account(id) },
          serializer: ->(raw) { ea.serialize(raw) }
        )
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                           is_read_only: false, is_sortable: true))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: false, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('scheme', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                             enum_values: ENUM_SCHEME, is_read_only: false, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                             is_read_only: true, is_sortable: true))
        add_field('sequence_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                    enum_values: ENUM_SEQUENCE_TYPE,
                                                    is_read_only: false, is_sortable: true))
        add_field('reference', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('unique_mandate_reference', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                               is_read_only: false, is_sortable: true))
        add_field('creditor_identifier', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                          is_read_only: false, is_sortable: false))
        add_field('signature_date', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                     is_read_only: false, is_sortable: true))
        add_field('signature_location', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                         is_read_only: false, is_sortable: false))
        add_field('creditor', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                               is_read_only: false, is_sortable: false))
        add_field('debtor', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                             is_read_only: false, is_sortable: false))
        add_field('debtor_account', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                     is_read_only: false, is_sortable: false))
        add_field('amendment_information', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                            is_read_only: false, is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                    is_read_only: false, is_sortable: false))
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
        add_field('external_account', ManyToOneSchema.new(
                                        foreign_collection: 'MambuExternalAccount',
                                        foreign_key: 'external_account_id',
                                        foreign_key_target: 'id'
                                      ))
      end
    end
  end
end

# rubocop:enable Metrics/ClassLength
