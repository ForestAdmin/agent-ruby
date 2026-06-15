# rubocop:disable Metrics/ClassLength
module ForestAdminDatasourceMambuPayments
  module Collections
    class DirectDebitMandate < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      ENUM_SEQUENCE_TYPE = %w[one_off recurrent first final].freeze
      ENUM_SCHEME = %w[sepa bacs ach].freeze

      client_resource :direct_debit_mandate

      def initialize(datasource)
        super(datasource, 'MambuDirectDebitMandate')
        define_schema
        define_relations
        reconcile_filter_operators!
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

      def collection_filters
        {
          'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] },
          'external_account_id' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      def many_to_one_embeds
        [
          { foreign_key: 'connected_account_id', relation_name: 'connected_account',
            collection: 'MambuConnectedAccount' },
          { foreign_key: 'external_account_id', relation_name: 'external_account',
            collection: 'MambuExternalAccount' }
        ]
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('connected_account_id', ColumnSchema.new(column_type: 'String',
                                                           is_read_only: false, is_sortable: true))
        add_field('external_account_id', ColumnSchema.new(column_type: 'String',
                                                          is_read_only: false, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: true))
        add_field('scheme', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_SCHEME,
                                             is_read_only: false, is_sortable: true))
        add_field('status', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true))
        add_field('sequence_type', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_SEQUENCE_TYPE,
                                                    is_read_only: false, is_sortable: true))
        add_field('reference', ColumnSchema.new(column_type: 'String', is_read_only: false, is_sortable: false))
        add_field('unique_mandate_reference', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                               is_sortable: true))
        add_field('creditor_identifier', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                          is_sortable: false))
        add_field('signature_date', ColumnSchema.new(column_type: 'Date', is_read_only: false, is_sortable: true))
        add_field('signature_location', ColumnSchema.new(column_type: 'String', is_read_only: false,
                                                         is_sortable: false))
        add_field('creditor', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('debtor', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('debtor_account', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('amendment_information', ColumnSchema.new(column_type: 'Json', is_read_only: false,
                                                            is_sortable: false))
        add_field('custom_fields', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
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
