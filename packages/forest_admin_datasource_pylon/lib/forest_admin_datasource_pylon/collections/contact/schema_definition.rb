module ForestAdminDatasourcePylon
  module Collections
    class Contact < CursorCollection
      # Every column is read-only in this story: writes land in a later one. No
      # column is sortable either — neither `GET /contacts` nor
      # `POST /contacts/search` exposes a sort parameter, so advertising a
      # sortable column would let the UI ask for an order the API cannot honour.
      #
      # Filter operators are not chosen here: they come from
      # `ApiFilters::API_FILTERS`, which mirrors the allow-list of the API. A
      # column missing from that table gets no operator, so the UI never offers
      # a filter Pylon would refuse. A contact carries no timestamp at all —
      # Pylon returns none.
      module SchemaDefinition
        ColumnSchema    = BaseCollection::ColumnSchema
        ManyToOneSchema = BaseCollection::ManyToOneSchema
        OneToManySchema = BaseCollection::OneToManySchema

        private

        def define_schema
          define_identity_fields
          define_contact_fields
          define_portal_fields
        end

        # `account_id` is both the key of the relation and a column the contacts
        # search filters, which is what lets the account side list its contacts
        # server-side and the embedder resolve the account of a page of contacts
        # in one request.
        #
        # `requested_issues` rather than `issues`: a contact is the requester of
        # an issue, never its assignee — that side belongs to PylonUser.
        def define_relations
          add_field('account', ManyToOneSchema.new(foreign_collection: 'PylonAccount',
                                                   foreign_key: 'account_id', foreign_key_target: 'id'))
          add_field('requested_issues', OneToManySchema.new(foreign_collection: 'PylonIssue',
                                                            origin_key: 'requester_id', origin_key_target: 'id'))
        end

        def define_identity_fields
          add_field('id', ColumnSchema.new(column_type: 'String',
                                           filter_operators: ApiFilters.forest_operators('id'),
                                           is_primary_key: true, is_read_only: true))
          add_column('name', 'String')
          # Flattened from the nested `{ id: ..., external_ids: ... }` object
          # Pylon returns, and kept as a column next to the `account` relation
          # it is the key of: the search endpoint filters it.
          add_column('account_id', 'String')
          # Read-only Json, and deliberately unfilterable although the search
          # endpoint does not offer it either: the API matches bare external-id
          # strings while the column shows `{external_id, label}` objects, so a
          # filter would run on something the operator cannot see.
          add_column('external_ids', 'Json')
        end

        # `email` and `primary_phone_number` carry the primary value; the lists
        # hold every address and number, and neither list is filterable.
        def define_contact_fields
          add_column('email', 'String')
          add_column('emails', 'Json')
          add_column('primary_phone_number', 'String')
          add_column('phone_numbers', 'Json')
          add_column('avatar_url', 'String')
        end

        def define_portal_fields
          # Left as String rather than Enum: Pylon documents no_access / member
          # / admin, but an organization can define its own portal roles, which
          # is what `portal_role_id` points at.
          add_column('portal_role', 'String')
          add_column('portal_role_id', 'String')
          add_column('integration_user_ids', 'Json')
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
