module ForestAdminDatasourcePylon
  module Collections
    class Account < CursorCollection
      # A column is writable when `POST /accounts` or `PATCH /accounts/{id}`
      # accepts it, in the shape it is read under — the Json columns holding
      # objects rather than plain strings are left read-only, see below. No
      # column is sortable — neither `GET /accounts` nor `POST /accounts/search`
      # exposes a sort parameter, so advertising a sortable column would let the
      # UI ask for an order the API cannot honour.
      #
      # Filter operators are not chosen here: they come from
      # `ApiFilters::API_FILTERS`, which mirrors the allow-list of the API. A
      # column missing from that table gets no operator, so the UI offers no
      # filter of this collection's own that Pylon would refuse — the absence
      # family the agent derives above the datasource being the exception
      # `Query::OperatorMaps::Table` describes.
      module SchemaDefinition
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
          add_column('id', 'String', is_primary_key: true)
          add_column('name', 'String', writable: true)
          # Left as String rather than Enum: Pylon ships customer / partner /
          # prospect but lets an organization define its own account types. It
          # is written under the name `account_type`, see `Account::RENAMES`.
          add_column('type', 'String', writable: true)
          # Writable on an update only: an account is created enabled.
          add_column('is_disabled', 'Boolean', writable: true)
        end

        # `domain` and `primary_domain` carry the same value; both are kept
        # because Pylon returns both, and only the `domains` list is filterable.
        # Neither is writable: `domains` is the list the API takes, and writing
        # one of its two projections would leave the other stale.
        def define_domain_fields
          add_column('domain', 'String')
          add_column('primary_domain', 'String')
          add_column('domains', 'Json', writable: true)
          add_column('tags', 'Json', writable: true)
        end

        def define_ownership_fields
          # Flattened from the nested `{ id: ..., email: ... }` object Pylon
          # returns; a plain column, see `define_relations` above.
          add_column('owner_id', 'String', writable: true)
          # Read-only although the endpoint takes it: the column shows
          # `{external_id, label}` objects, and what the API writes back is not
          # documented in that shape — writing one for the other would replace
          # the ids of the account with something it cannot read.
          add_column('external_ids', 'Json')
        end

        # Both belong to the integrations Pylon syncs them from: `crm_settings`
        # is absent from every write endpoint, and `channels` — which they do
        # take — is a list of objects whose write shape the reference does not
        # document, the same reason `external_ids` stays read-only above.
        def define_integration_fields
          add_column('channels', 'Json')
          add_column('crm_settings', 'Json')
        end

        def define_time_fields
          %w[created_at updated_at latest_customer_activity_time].each { |field| add_column(field, 'Date') }
        end
      end
    end
  end
end
