module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      # Every column is read-only in this story: writes land in a later one. No
      # column is sortable either — `/issues/search` exposes no sort parameter at
      # all, results always come back ordered by `created_at` descending, so
      # advertising a sortable column would let the UI ask for an order the API
      # cannot honour.
      #
      # Filter operators are not chosen here: they come from
      # `ApiFilters::API_FILTERS`, which mirrors the allow-list of the API. A
      # column missing from that table gets no operator, so the UI never offers
      # a filter Pylon would refuse.
      module SchemaDefinition
        ColumnSchema = BaseCollection::ColumnSchema
        Operators    = BaseCollection::Operators

        private

        def define_schema
          define_identity_fields
          define_content_fields
          define_party_fields
          define_time_fields
        end

        # Relations are declared in a later story, once the Account / Contact /
        # User / Team collections exist to point at.
        def define_relations; end

        def define_identity_fields
          # Only equal/in: these are the two the primary-key short-circuit can
          # actually serve through GET /issues/{id}. `id` is not part of the
          # search allow-list, so it never reaches the translator.
          add_field('id', ColumnSchema.new(column_type: 'String',
                                           filter_operators: [Operators::EQUAL, Operators::IN],
                                           is_primary_key: true, is_read_only: true))
          add_column('number', 'Number')
          add_column('link', 'String')
        end

        def define_content_fields
          add_column('title', 'String')
          add_column('body_html', 'String')
          # Left as String rather than Enum: Pylon ships five built-in states
          # but organisations define their own on top of them.
          add_column('state', 'String')
          add_column('type', 'String')
          add_column('source', 'String')
          add_column('tags', 'Json')
          add_column('customer_portal_visible', 'Boolean')
          add_column('author_unverified', 'Boolean')
          add_column('number_of_touches', 'Number')
        end

        # Flattened from the nested `{id: …}` objects Pylon returns. They stay
        # plain columns until the story that adds the related collections.
        def define_party_fields
          %w[account_id requester_id assignee_id team_id].each { |field| add_column(field, 'String') }
        end

        def define_time_fields
          %w[first_response_time resolution_time latest_message_time created_at updated_at].each do |field|
            add_column(field, 'Date')
          end
          %w[time_in_status_seconds business_hours_time_in_status_seconds].each do |field|
            add_column(field, 'Json')
          end
        end

        def add_column(name, type)
          add_field(name, ColumnSchema.new(column_type: type,
                                           filter_operators: ApiFilters.forest_operators(name),
                                           is_read_only: true))
        end
      end
    end
  end
end
