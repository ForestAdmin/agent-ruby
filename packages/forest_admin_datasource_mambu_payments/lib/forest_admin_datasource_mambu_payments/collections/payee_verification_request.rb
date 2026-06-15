module ForestAdminDatasourceMambuPayments
  module Collections
    # Payee Verification Requests are emitted by Numeral when an outgoing
    # verification is sent (via the `Trigger payee verification` smart
    # action on external accounts) or when an incoming verification arrives
    # from the network. From Forest's perspective they are read-only: send
    # and simulate are lifecycle operations exposed as smart-action plugins
    # (see TriggerPayeeVerification) rather than collection writes.
    class PayeeVerificationRequest < BaseCollection
      ENUM_STATUS          = %w[completed failed].freeze
      ENUM_FAILURE_CODE    = %w[business_error technical_error psp_technical_error].freeze
      ENUM_DIRECTION       = %w[outgoing incoming].freeze
      ENUM_SCHEME          = %w[vop].freeze
      ENUM_MATCHING_RESULT = %w[match close_match no_match impossible_match].freeze

      client_resource :payee_verification_request

      def initialize(datasource)
        super(datasource, 'MambuPayeeVerificationRequest')
        define_schema
        reconcile_filter_operators!
      end

      def serialize(record)
        a = attrs_of(record)
        {
          'id' => a['id'],
          'object' => a['object'],
          'status' => a['status'],
          'failure_code' => a['failure_code'],
          'status_details' => a['status_details'],
          'direction' => a['direction'],
          'scheme' => a['scheme'],
          'request' => a['request'],
          'matching_result' => a['matching_result'],
          'payee_suggested_name' => a['payee_suggested_name'],
          'matching_details' => a['matching_details'],
          'scheme_data' => a['scheme_data'],
          'metadata' => a['metadata'],
          'response_received_at' => a['response_received_at'],
          'created_at' => a['created_at']
        }
      end

      protected

      def collection_filters
        {
          'status' => { ops: [Operators::EQUAL, Operators::IN] },
          'direction' => { ops: [Operators::EQUAL, Operators::IN] },
          'scheme' => { ops: [Operators::EQUAL, Operators::IN] },
          'matching_result' => { ops: [Operators::EQUAL, Operators::IN] }
        }
      end

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                         is_read_only: true, is_sortable: true))
        add_field('object', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_STATUS,
                                             is_read_only: true, is_sortable: true))
        add_field('failure_code', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_FAILURE_CODE,
                                                   is_read_only: true, is_sortable: false))
        add_field('status_details', ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: false))
        add_field('direction', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_DIRECTION,
                                                is_read_only: true, is_sortable: true))
        add_field('scheme', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_SCHEME,
                                             is_read_only: true, is_sortable: true))
        # request, matching_details, scheme_data are nested objects with their
        # own sub-fields (payee_identification, scheme_request_id, ...). Forest
        # can't model nested columns natively, so we expose them as Json
        # snapshots — matches how IncomingPayment handles originating_account.
        add_field('request', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('matching_result', ColumnSchema.new(column_type: 'Enum', enum_values: ENUM_MATCHING_RESULT,
                                                      is_read_only: true, is_sortable: true))
        add_field('payee_suggested_name', ColumnSchema.new(column_type: 'String', is_read_only: true,
                                                           is_sortable: false))
        add_field('matching_details', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('scheme_data', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('metadata', ColumnSchema.new(column_type: 'Json', is_read_only: true, is_sortable: false))
        add_field('response_received_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', is_read_only: true, is_sortable: true))
      end
    end
  end
end
