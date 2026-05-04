module ForestAdminDatasourceZendesk
  module Collections
    class User < BaseCollection
      include Searchable

      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema
      ENUM_ROLE       = %w[end-user agent admin].freeze

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

      def create(_caller, data)
        payload = build_payload(data)
        created = datasource.client.create_user(payload)
        serialize(created)
      end

      def update(caller, filter, patch)
        ids = ids_for(caller, filter)
        payload = build_payload(patch)
        ids.each { |id| datasource.client.update_user(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_user(id) }
      end

      protected

      def zendesk_resource = 'user'
      def sortable_fields  = ZENDESK_SORTABLE
      def find_one(id)     = datasource.client.find_user(id)

      private

      # Translates a Forest flat hash into a Zendesk user payload, folding
      # custom-field columns into the keyed `user_fields` hash.
      def build_payload(data)
        attrs = data.transform_keys(&:to_s)
        cf_keys = @custom_fields.to_h { |cf| [cf[:column_name], cf[:zendesk_key]] }
        user_fields = {}
        base = attrs.each_with_object({}) do |(k, v), h|
          if (key = cf_keys[k])
            user_fields[key] = v
          else
            h[k] = v
          end
        end
        %w[id created_at updated_at].each { |k| base.delete(k) }
        base['user_fields'] = user_fields unless user_fields.empty?
        base
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('email', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                            is_read_only: false, is_sortable: false))
        add_field('name', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                           is_read_only: false, is_sortable: true))
        add_field('role', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                           enum_values: ENUM_ROLE, is_read_only: false, is_sortable: false))
        add_field('phone', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                            is_read_only: false, is_sortable: false))
        add_field('organization_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                      is_read_only: false, is_sortable: false))
        add_field('time_zone', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                is_read_only: false, is_sortable: false))
        add_field('locale', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                             is_read_only: false, is_sortable: false))
        add_field('verified', ColumnSchema.new(column_type: 'Boolean', filter_operators: STRING_OPS,
                                               is_read_only: false, is_sortable: false))
        add_field('suspended', ColumnSchema.new(column_type: 'Boolean', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('updated_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))

        @custom_fields.each { |cf| add_field(cf[:column_name], cf[:schema]) }
      end

      def define_relations
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
        result = base_attributes(attrs)
        user_fields = attrs['user_fields'] || {}
        @custom_fields.each { |cf| result[cf[:column_name]] = user_fields[cf[:zendesk_key]] }
        result
      end

      def base_attributes(attrs)
        {
          'id' => attrs['id'], 'email' => attrs['email'], 'name' => attrs['name'],
          'role' => attrs['role'], 'phone' => attrs['phone'],
          'organization_id' => attrs['organization_id'],
          'time_zone' => attrs['time_zone'], 'locale' => attrs['locale'],
          'verified' => attrs['verified'], 'suspended' => attrs['suspended'],
          'created_at' => attrs['created_at'], 'updated_at' => attrs['updated_at']
        }
      end
    end
  end
end
