module ForestAdminDatasourceZendesk
  module Collections
    class Organization < BaseCollection
      include Searchable

      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema

      ZENDESK_SORTABLE = {
        'created_at' => 'created_at',
        'updated_at' => 'updated_at',
        'name' => 'name'
      }.freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'ZendeskOrganization')
        @custom_fields = custom_fields
        define_schema
        define_relations
        enable_search
        enable_count
      end

      protected

      def zendesk_resource = 'organization'
      def sortable_fields  = ZENDESK_SORTABLE
      def find_one(id)     = datasource.client.find_organization(id)

      private

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: true, is_sortable: true))
        add_field('domain_names', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                                   is_read_only: true, is_sortable: false))
        add_field('details', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                              is_read_only: true, is_sortable: false))
        add_field('notes', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                            is_read_only: true, is_sortable: false))
        add_field('group_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                               is_read_only: true, is_sortable: false))
        add_field('shared_tickets', ColumnSchema.new(column_type: 'Boolean', filter_operators: [],
                                                     is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('updated_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))

        @custom_fields.each { |cf| add_field(cf[:column_name], cf[:schema]) }
      end

      def define_relations
        add_field('users', OneToManySchema.new(
                             foreign_collection: 'ZendeskUser',
                             origin_key: 'organization_id',
                             origin_key_target: 'id'
                           ))
        add_field('tickets', OneToManySchema.new(
                               foreign_collection: 'ZendeskTicket',
                               origin_key: 'organization_id',
                               origin_key_target: 'id'
                             ))
      end

      def serialize(org)
        attrs = attrs_of(org)
        result = base_attributes(attrs)
        org_fields = attrs['organization_fields'] || {}
        @custom_fields.each { |cf| result[cf[:column_name]] = org_fields[cf[:zendesk_key]] }
        result
      end

      def base_attributes(attrs)
        {
          'id' => attrs['id'], 'name' => attrs['name'],
          'domain_names' => attrs['domain_names'], 'details' => attrs['details'],
          'notes' => attrs['notes'], 'group_id' => attrs['group_id'],
          'shared_tickets' => attrs['shared_tickets'],
          'created_at' => attrs['created_at'], 'updated_at' => attrs['updated_at']
        }
      end
    end
  end
end
