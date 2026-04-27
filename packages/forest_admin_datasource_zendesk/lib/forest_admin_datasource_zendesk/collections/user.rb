module ForestAdminDatasourceZendesk
  module Collections
    class User < BaseCollection
      ManyToOneSchema  = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      OneToManySchema  = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema
      ENUM_ROLE        = %w[end-user agent admin].freeze

      ZENDESK_SORTABLE = {
        'created_at' => 'created_at',
        'updated_at' => 'updated_at',
        'name' => 'name'
      }.freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'ZendeskUser')
        @custom_fields = custom_fields
        define_schema
        define_relations
        enable_search
        enable_count
      end

      def list(caller, filter, projection)
        timezone = timezone_for(caller)
        ids = extract_id_lookup(filter.condition_tree)
        records = if ids
                    ids.filter_map { |id| datasource.client.find_user(id) }
                  else
                    query = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.call(
                      filter.condition_tree, timezone: timezone
                    )
                    sort_by, sort_order = translate_sort(filter.sort, ZENDESK_SORTABLE)
                    page, per_page      = translate_page(filter.page)
                    datasource.client.search('user', query: query, sort_by: sort_by, sort_order: sort_order,
                                                     page: page, per_page: per_page)
                  end
        records.map { |u| project(serialize(u), projection) }
      end

      def aggregate(caller, filter, aggregation, _limit = nil)
        unless aggregation.operation == 'Count' && aggregation.field.nil? && aggregation.groups.empty?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Zendesk datasource only supports Count aggregation without groups.'
        end

        query = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.call(
          filter.condition_tree, timezone: timezone_for(caller)
        )
        count = datasource.client.count('user', query: [query, filter.search].compact.reject(&:empty?).join(' '))
        [{ 'value' => count, 'group' => {} }]
      end

      private

      def define_schema
        add_field('id',              ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                      is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('email',           ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                      is_read_only: true, is_sortable: false))
        add_field('name',            ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                      is_read_only: true, is_sortable: true))
        add_field('role',            ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                      enum_values: ENUM_ROLE, is_read_only: true, is_sortable: false))
        add_field('phone',           ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                      is_read_only: true, is_sortable: false))
        add_field('organization_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                      is_read_only: true, is_sortable: false))
        add_field('time_zone',       ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                      is_read_only: true, is_sortable: false))
        add_field('locale',          ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                      is_read_only: true, is_sortable: false))
        add_field('verified',        ColumnSchema.new(column_type: 'Boolean', filter_operators: STRING_OPS,
                                                      is_read_only: true, is_sortable: false))
        add_field('suspended',       ColumnSchema.new(column_type: 'Boolean', filter_operators: STRING_OPS,
                                                      is_read_only: true, is_sortable: false))
        add_field('created_at',      ColumnSchema.new(column_type: 'Date',   filter_operators: DATE_OPS,
                                                      is_read_only: true, is_sortable: true))
        add_field('updated_at',      ColumnSchema.new(column_type: 'Date',   filter_operators: DATE_OPS,
                                                      is_read_only: true, is_sortable: true))

        @custom_fields.each do |cf|
          add_field(cf[:column_name], cf[:schema])
        end
      end

      def define_relations
        # Org relation depends on the Organization collection existing in the datasource.
        # We declare the relation regardless; if the collection isn't registered, Forest
        # will surface a clear error when something tries to traverse it.
        add_field('organization', ManyToOneSchema.new(
                                    foreign_collection: 'ZendeskOrganization',
                                    foreign_key: 'organization_id',
                                    foreign_key_target: 'id'
                                  ))
        add_field('requested_tickets', OneToManySchema.new(
                                         foreign_collection: 'ZendeskTicket',
                                         origin_key: 'requester_id',
                                         origin_key_target: 'id'
                                       ))
      end

      def serialize(user)
        attrs = attrs_of(user)
        result = {
          'id' => attrs['id'],
          'email' => attrs['email'],
          'name' => attrs['name'],
          'role' => attrs['role'],
          'phone' => attrs['phone'],
          'organization_id' => attrs['organization_id'],
          'time_zone' => attrs['time_zone'],
          'locale' => attrs['locale'],
          'verified' => attrs['verified'],
          'suspended' => attrs['suspended'],
          'created_at' => attrs['created_at'],
          'updated_at' => attrs['updated_at']
        }

        user_fields = attrs['user_fields'] || {}
        @custom_fields.each do |cf|
          result[cf[:column_name]] = user_fields[cf[:zendesk_key]]
        end

        result
      end
    end
  end
end
