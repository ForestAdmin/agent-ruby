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
      # column missing from that table gets no operator, so the UI offers no
      # filter of this collection's own that Pylon would refuse — the absence
      # family the agent derives above the datasource being the exception
      # `Query::OperatorMaps::Table` describes.
      module SchemaDefinition
        ColumnSchema    = BaseCollection::ColumnSchema
        ManyToOneSchema = BaseCollection::ManyToOneSchema
        Operators       = BaseCollection::Operators

        private

        def define_schema
          define_identity_fields
          define_content_fields
          define_party_fields
          define_time_fields
        end

        # The four parties of an issue, each pointing at the collection owning its
        # shape: the flattened `*_id` columns stay, as the keys the relation is
        # read through and as the columns the search endpoint filters.
        #
        # RelationEmbedder resolves them at read time, in bulk. The reverse sides
        # are declared by the collections they belong to; `/issues/search`
        # filters every one of these keys, so they are answered server-side.
        def define_relations
          add_field('account', ManyToOneSchema.new(foreign_collection: 'PylonAccount',
                                                   foreign_key: 'account_id', foreign_key_target: 'id'))
          add_field('requester', ManyToOneSchema.new(foreign_collection: 'PylonContact',
                                                     foreign_key: 'requester_id', foreign_key_target: 'id'))
          add_field('assignee', ManyToOneSchema.new(foreign_collection: 'PylonUser',
                                                    foreign_key: 'assignee_id', foreign_key_target: 'id'))
          add_field('team', ManyToOneSchema.new(foreign_collection: 'PylonTeam',
                                                foreign_key: 'team_id', foreign_key_target: 'id'))
        end

        def define_identity_fields
          # Only equal/in: these are the two the primary-key short-circuit can
          # actually serve through GET /issues/{id}. `id` is not part of the
          # search allow-list, so it never reaches the translator.
          add_field('id', ColumnSchema.new(column_type: 'String',
                                           filter_operators: [Operators::EQUAL, Operators::IN],
                                           is_primary_key: true, is_groupable: false, is_read_only: true))
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
          define_thread_field
        end

        # The conversation, embedded at read time by MessagesEmbedder. Declared
        # by hand rather than through `add_column`: its type is the shape of one
        # message, not a primitive.
        #
        # Neither filterable nor sortable — `POST /issues/search` covers no
        # message field, and the thread is not even part of the payload the
        # search endpoint returns — and not groupable either: `ColumnSchema`
        # defaults that flag to true, where the `add_column` of the base passes
        # false for every Pylon column, a thread being both an array and a value
        # the pages of a cursor walk do not carry.
        def define_thread_field
          add_field('messages', ColumnSchema.new(column_type: [Issue::MESSAGE_THREAD_SCHEMA],
                                                 filter_operators: [], is_groupable: false,
                                                 is_read_only: true))
        end

        # Flattened from the nested `{id: …}` objects Pylon returns, and kept as
        # columns next to the relations they are the keys of: they are what the
        # search endpoint filters, on this side and on the reverse one.
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
      end
    end
  end
end
