module ForestAdminDatasourceZendesk
  module Collections
    class Ticket < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema

      ENUM_STATUS   = %w[new open pending hold solved closed].freeze
      ENUM_PRIORITY = %w[low normal high urgent].freeze
      ENUM_TYPE     = %w[problem incident question task].freeze

      ZENDESK_SORTABLE = {
        'updated_at' => 'updated_at',
        'created_at' => 'created_at',
        'priority' => 'priority',
        'status' => 'status',
        'ticket_type' => 'ticket_type'
      }.freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'ZendeskTicket')
        @custom_fields = custom_fields
        define_schema
        define_relations
        enable_search
        enable_count
      end

      def list(caller, filter, projection)
        records = fetch_records(filter, timezone_for(caller))
        emails  = needs_requester_email?(projection) ? bulk_fetch_emails(records) : {}
        rows    = records.map { |t| project(serialize(t, emails), projection) }
        embed_relations(records, rows, projection)
        rows
      end

      protected

      def aggregate_count(caller, filter)
        datasource.client.count('ticket', query: build_query(filter, timezone_for(caller)))
      end

      private

      def fetch_records(filter, timezone)
        ids = extract_id_lookup(filter.condition_tree)
        return ids.filter_map { |id| datasource.client.find_ticket(id) } if ids

        query = build_query(filter, timezone)
        sort_by, sort_order = translate_sort(filter.sort, ZENDESK_SORTABLE)
        page, per_page      = translate_page(filter.page)

        datasource.client.search('ticket', query: query, sort_by: sort_by, sort_order: sort_order,
                                           page: page, per_page: per_page)
      end

      def needs_requester_email?(projection)
        projection.nil? || Array(projection).map(&:to_s).include?('requester_email')
      end

      def bulk_fetch_emails(records)
        ids = records.map { |t| attrs_of(t)['requester_id'] }
        datasource.client.fetch_user_emails(ids)
      end

      def build_query(filter, timezone)
        translated = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.call(
          filter.condition_tree, timezone: timezone
        )
        [translated, filter.search].compact.reject(&:empty?).join(' ')
      end

      # Embeds requester/assignee/organization (ManyToOne) when their projection
      # paths are requested. Reads FK values from the source Zendesk records
      # (not the projected rows, whose FK columns may have been stripped) and
      # writes onto rows by index.
      def embed_relations(records, rows, projection)
        return if projection.nil?

        relations = relations_in(projection)
        return if relations.empty?

        sources = records.map { |t| attrs_of(t) }
        embed_users(rows, sources, relations) if (relations & %w[requester assignee]).any?
        embed_organizations(rows, sources) if relations.include?('organization')
      end

      def embed_users(rows, sources, relations)
        ids = sources.flat_map { |a| [a['requester_id'], a['assignee_id']] }.compact.uniq
        users = datasource.client.fetch_users_by_ids(ids)
        rows.each_with_index do |row, i|
          row['requester'] = serialized_user(users[sources[i]['requester_id']]) if relations.include?('requester')
          row['assignee']  = serialized_user(users[sources[i]['assignee_id']]) if relations.include?('assignee')
        end
      end

      def embed_organizations(rows, sources)
        ids = sources.filter_map { |a| a['organization_id'] }.uniq
        orgs = datasource.client.fetch_organizations_by_ids(ids)
        rows.each_with_index do |row, i|
          row['organization'] = serialized_org(orgs[sources[i]['organization_id']])
        end
      end

      def relations_in(projection)
        Array(projection).map(&:to_s).filter_map { |p| p.split(':').first if p.include?(':') }.uniq
      end

      def serialized_user(raw)
        return nil if raw.nil?

        attrs = raw.is_a?(Hash) ? raw : attrs_of(raw)
        {
          'id' => attrs['id'], 'email' => attrs['email'], 'name' => attrs['name'],
          'role' => attrs['role'], 'organization_id' => attrs['organization_id'],
          'phone' => attrs['phone'], 'time_zone' => attrs['time_zone'],
          'locale' => attrs['locale'], 'verified' => attrs['verified'],
          'suspended' => attrs['suspended'], 'created_at' => attrs['created_at'],
          'updated_at' => attrs['updated_at']
        }
      end

      def serialized_org(raw)
        return nil if raw.nil?

        attrs = raw.is_a?(Hash) ? raw : attrs_of(raw)
        {
          'id' => attrs['id'], 'name' => attrs['name'],
          'domain_names' => attrs['domain_names'], 'details' => attrs['details'],
          'notes' => attrs['notes'], 'group_id' => attrs['group_id'],
          'shared_tickets' => attrs['shared_tickets'],
          'created_at' => attrs['created_at'], 'updated_at' => attrs['updated_at']
        }
      end

      def define_schema
        add_field('id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                         is_primary_key: true, is_read_only: true, is_sortable: true))
        add_field('subject', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                              is_read_only: true, is_sortable: false))
        add_field('description', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('status', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                             enum_values: ENUM_STATUS, is_read_only: true, is_sortable: true))
        add_field('priority', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                               enum_values: ENUM_PRIORITY, is_read_only: true, is_sortable: true))
        add_field('ticket_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                  enum_values: ENUM_TYPE, is_read_only: true, is_sortable: true))
        add_field('requester_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                   is_read_only: true, is_sortable: true))
        add_field('assignee_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                  is_read_only: true, is_sortable: true))
        add_field('group_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                               is_read_only: true, is_sortable: true))
        add_field('organization_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                      is_read_only: true, is_sortable: true))
        add_field('external_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                  is_read_only: true, is_sortable: false))
        add_field('requester_email', ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL],
                                                      is_read_only: true, is_sortable: false))
        add_field('tags', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                           is_read_only: true, is_sortable: false))
        add_field('url', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                          is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))
        add_field('updated_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                 is_read_only: true, is_sortable: true))

        @custom_fields.each { |cf| add_field(cf[:column_name], cf[:schema]) }
      end

      def define_relations
        add_field('requester', ManyToOneSchema.new(
                                 foreign_collection: 'ZendeskUser',
                                 foreign_key: 'requester_id',
                                 foreign_key_target: 'id'
                               ))
        add_field('assignee', ManyToOneSchema.new(
                                foreign_collection: 'ZendeskUser',
                                foreign_key: 'assignee_id',
                                foreign_key_target: 'id'
                              ))
        add_field('organization', ManyToOneSchema.new(
                                    foreign_collection: 'ZendeskOrganization',
                                    foreign_key: 'organization_id',
                                    foreign_key_target: 'id'
                                  ))
        add_field('comments', OneToManySchema.new(
                                foreign_collection: 'ZendeskComment',
                                origin_key: 'ticket_id',
                                origin_key_target: 'id'
                              ))
      end

      def serialize(ticket, emails = {})
        attrs = attrs_of(ticket)
        result = base_attributes(attrs, emails)
        cf_values = Array(attrs['custom_fields']).to_h { |f| [f['id'], f['value']] }
        @custom_fields.each { |cf| result[cf[:column_name]] = cf_values[cf[:zendesk_id]] }
        result
      end

      def base_attributes(attrs, emails)
        {
          'id' => attrs['id'], 'subject' => attrs['subject'],
          'description' => attrs['description'], 'status' => attrs['status'],
          'priority' => attrs['priority'], 'ticket_type' => attrs['type'],
          'requester_id' => attrs['requester_id'], 'assignee_id' => attrs['assignee_id'],
          'group_id' => attrs['group_id'], 'organization_id' => attrs['organization_id'],
          'external_id' => attrs['external_id'],
          'requester_email' => emails[attrs['requester_id']],
          'tags' => attrs['tags'], 'url' => attrs['url'],
          'created_at' => attrs['created_at'], 'updated_at' => attrs['updated_at']
        }
      end
    end
  end
end
