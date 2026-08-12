module ForestAdminDatasourcePylon
  module Collections
    class Account < CursorCollection
      # Every column is read-only in this story: writes land in a later one. No
      # column is sortable either — neither `GET /accounts` nor
      # `POST /accounts/search` exposes a sort parameter, so advertising a
      # sortable column would let the UI ask for an order the API cannot honour.
      #
      # Filter operators are not chosen here: they come from
      # `ApiFilters::API_FILTERS`, which mirrors the allow-list of the API. A
      # column missing from that table gets no operator, so the UI never offers
      # a filter Pylon would refuse.
      module SchemaDefinition
        ColumnSchema    = BaseCollection::ColumnSchema
        OneToManySchema = BaseCollection::OneToManySchema

        private

        def define_schema
          define_identity_fields
          define_domain_fields
          define_ownership_fields
          define_integration_fields
          define_time_fields
        end

        # The reverse sides of the two ManyToOne relations pointing here. Both
        # `/issues/search` and `/contacts/search` filter `account_id`
        # server-side, so a related list is one request and no in-memory pass.
        #
        # `owner_id` stays a plain column: it does point at a PylonUser, and the
        # embedder would resolve it like any other key, but nothing in the panel
        # asks for the owner of an account yet.
        def define_relations
          add_field('issues', OneToManySchema.new(foreign_collection: 'PylonIssue',
                                                  origin_key: 'account_id', origin_key_target: 'id'))
          add_field('contacts', OneToManySchema.new(foreign_collection: 'PylonContact',
                                                    origin_key: 'account_id', origin_key_target: 'id'))
        end

        def define_identity_fields
          add_field('id', ColumnSchema.new(column_type: 'String',
                                           filter_operators: ApiFilters.forest_operators('id'),
                                           is_primary_key: true, is_read_only: true))
          add_column('name', 'String')
          # Left as String rather than Enum: Pylon ships customer / partner /
          # prospect but lets an organization define its own account types.
          add_column('type', 'String')
          add_column('is_disabled', 'Boolean')
        end

        # `domain` and `primary_domain` carry the same value; both are kept
        # because Pylon returns both, and only the `domains` list is filterable.
        def define_domain_fields
          add_column('domain', 'String')
          add_column('primary_domain', 'String')
          add_column('domains', 'Json')
          add_column('tags', 'Json')
        end

        def define_ownership_fields
          # Flattened from the nested `{ id: ..., email: ... }` object Pylon
          # returns; a plain column, see `define_relations` above.
          add_column('owner_id', 'String')
          add_column('external_ids', 'Json')
        end

        def define_integration_fields
          add_column('channels', 'Json')
          add_column('crm_settings', 'Json')
        end

        def define_time_fields
          %w[created_at updated_at latest_customer_activity_time].each { |field| add_column(field, 'Date') }
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
