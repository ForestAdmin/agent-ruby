module ForestAdminDatasourceZendesk
  module Collections
    class Ticket < BaseCollection
      include SchemaDefinition
      include RelationEmbedder
      include CommentsEmbedder
      include Serializer

      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

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

      COMMENT_THREAD_SCHEMA = {
        'id' => 'Number',
        'body' => 'String',
        'html_body' => 'String',
        'public' => 'Boolean',
        'author_email' => 'String',
        'author_name' => 'String',
        'created_at' => 'Date'
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
        records = fetch_records(caller, filter)
        emails  = needs_requester_email?(projection) ? bulk_fetch_emails(records) : {}
        rows    = records.map { |t| project(serialize(t, emails), projection) }
        embed_relations(records, rows, projection)
        embed_comments(records, rows) if want_comments?(projection)
        rows
      end

      def create(_caller, data)
        payload = build_payload(data, on_create: true)
        created = datasource.client.create_ticket(payload)
        serialize(created)
      end

      def update(caller, filter, patch)
        ids = ids_for(caller, filter)
        payload = build_payload(patch, on_create: false)
        ids.each { |id| datasource.client.update_ticket(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| datasource.client.delete_ticket(id) }
      end

      protected

      def aggregate_count(caller, filter)
        datasource.client.count('ticket', query: build_zendesk_query(caller, filter))
      end

      private

      # `description` only writes the initial comment at creation time; Zendesk
      # has no update path for it, so it's dropped on patch.
      def build_payload(data, on_create:)
        attrs = data.transform_keys(&:to_s)
        custom_fields, base = split_custom_fields(attrs)
        %w[id requester_email url created_at updated_at].each { |k| base.delete(k) }
        base['type'] = base.delete('ticket_type') if base.key?('ticket_type')

        description = base.delete('description')
        base['comment'] = { 'body' => description } if on_create && description && !description.empty?

        base['custom_fields'] = custom_fields unless custom_fields.empty?
        base
      end

      def split_custom_fields(attrs)
        cf_by_column = @custom_fields.to_h { |cf| [cf[:column_name], cf[:zendesk_id]] }
        custom = []
        rest = attrs.each_with_object({}) do |(k, v), h|
          if (zendesk_id = cf_by_column[k])
            custom << { 'id' => zendesk_id, 'value' => v }
          else
            h[k] = v
          end
        end
        [custom, rest]
      end

      def fetch_records(caller, filter)
        ids = extract_id_lookup(filter.condition_tree)
        if ids
          by_id = datasource.client.fetch_tickets_by_ids(ids)
          return ids.filter_map { |id| by_id[id] }
        end

        sort_by, sort_order = translate_sort(filter.sort, ZENDESK_SORTABLE)
        page, per_page      = translate_page(filter.page)

        datasource.client.search('ticket', query: build_zendesk_query(caller, filter),
                                           sort_by: sort_by, sort_order: sort_order,
                                           page: page, per_page: per_page)
      end

      def needs_requester_email?(projection)
        projection.nil? || Array(projection).map(&:to_s).include?('requester_email')
      end

      def bulk_fetch_emails(records)
        ids = records.map { |t| attrs_of(t)['requester_id'] }
        datasource.client.fetch_user_emails(ids)
      end
    end
  end
end
