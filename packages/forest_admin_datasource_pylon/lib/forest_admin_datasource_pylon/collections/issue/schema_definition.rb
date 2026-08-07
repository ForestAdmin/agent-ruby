module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      # Every column is read-only and non-sortable in this story: writes land in
      # a later story, and `/issues/search` exposes no sort parameter at all —
      # results always come back ordered by `created_at` descending, so
      # advertising a sortable column would let the UI ask for an order the API
      # cannot honour.
      module SchemaDefinition
        ColumnSchema = BaseCollection::ColumnSchema
        Operators    = BaseCollection::Operators
        STRING_OPS   = BaseCollection::STRING_OPS
        NUMBER_OPS   = BaseCollection::NUMBER_OPS
        DATE_OPS     = BaseCollection::DATE_OPS

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
          # actually serve through GET /issues/{id}.
          add_field('id', ColumnSchema.new(column_type: 'String',
                                           filter_operators: [Operators::EQUAL, Operators::IN],
                                           is_primary_key: true, is_read_only: true))
          add_field('number', column('Number', NUMBER_OPS))
          add_field('link', column('String', []))
        end

        def define_content_fields
          add_field('title', column('String', STRING_OPS))
          add_field('body_html', column('String', []))
          # Left as String rather than Enum: Pylon ships five built-in states
          # but organisations define their own on top of them.
          add_field('state', column('String', STRING_OPS))
          add_field('type', column('String', STRING_OPS))
          add_field('source', column('String', STRING_OPS))
          add_field('tags', column('Json', []))
          add_field('customer_portal_visible', column('Boolean', []))
          add_field('author_unverified', column('Boolean', []))
          add_field('number_of_touches', column('Number', NUMBER_OPS))
        end

        # Flattened from the nested `{id: …}` objects Pylon returns. They stay
        # plain columns until the story that adds the related collections.
        def define_party_fields
          %w[account_id requester_id assignee_id team_id].each do |field|
            add_field(field, column('String', STRING_OPS))
          end
        end

        def define_time_fields
          %w[first_response_time resolution_time latest_message_time created_at updated_at].each do |field|
            add_field(field, column('Date', DATE_OPS))
          end
          %w[time_in_status_seconds business_hours_time_in_status_seconds].each do |field|
            add_field(field, column('Json', []))
          end
        end

        def column(type, operators)
          ColumnSchema.new(column_type: type, filter_operators: operators, is_read_only: true)
        end
      end
    end
  end
end
