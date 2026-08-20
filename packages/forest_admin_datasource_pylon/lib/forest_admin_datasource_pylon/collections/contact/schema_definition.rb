module ForestAdminDatasourcePylon
  module Collections
    class Contact < CursorCollection
      # A column is writable when `POST /contacts` or `PATCH /contacts/{id}`
      # accepts it, in the shape it is read under — the Json columns holding
      # objects rather than plain strings are left read-only, see below. No
      # column is sortable — neither `GET /contacts` nor `POST /contacts/search`
      # exposes a sort parameter, so advertising a sortable column would let the
      # UI ask for an order the API cannot honour.
      #
      # Filter operators are not chosen here: they come from
      # `ApiFilters::API_FILTERS`, which mirrors the allow-list of the API. A
      # column missing from that table gets no operator, so the UI offers no
      # filter of this collection's own that Pylon would refuse — the absence
      # family the agent derives above the datasource being the exception
      # `Query::OperatorMaps::Table` describes. A contact carries no timestamp at all —
      # Pylon returns none.
      module SchemaDefinition
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
          add_column('id', 'String', is_primary_key: true)
          add_column('name', 'String', writable: true)
          # Flattened from the nested `{ id: ..., external_ids: ... }` object
          # Pylon returns, and kept as a column next to the `account` relation
          # it is the key of: the search endpoint filters it. Writable, which is
          # what opens the relation editor — see the party fields of PylonIssue
          # for why the key itself stays read-only in the Forest schema.
          add_column('account_id', 'String', writable: true)
          # Read-only Json, and deliberately unfilterable although the search
          # endpoint does not offer it either: the API matches bare external-id
          # strings while the column shows `{external_id, label}` objects, so a
          # filter would run on something the operator cannot see.
          add_column('external_ids', 'Json')
        end

        # `email` and `primary_phone_number` carry the primary value; the lists
        # hold every address and number, and neither list is filterable.
        #
        # `email` is written on a create and `emails` on an update, one
        # direction each: `POST /contacts` takes the primary address alone, and
        # the other ones are set on an existing contact. Two writable
        # projections of the same addresses would otherwise travel in one patch,
        # the list leaving out whatever the primary carries — the reason
        # PylonAccount keeps `domain` read-only next to `domains`.
        #
        # `phone_numbers` is not writable at all: it holds objects, and the
        # shape the endpoint takes them in is not the one the column shows.
        def define_contact_fields
          add_column('email', 'String', writable: true)
          add_column('emails', 'Json', writable: true)
          add_column('primary_phone_number', 'String', writable: true)
          add_column('phone_numbers', 'Json')
          add_column('avatar_url', 'String', writable: true)
        end

        def define_portal_fields
          # Left as String rather than Enum: Pylon documents no_access / member
          # / admin, but an organization can define its own portal roles, which
          # is what `portal_role_id` points at. The id is the one written and
          # the name is read-only, like `role_id` and `role_name` on PylonUser:
          # writing both would carry two projections of one role in the same
          # patch, and whichever Pylon ignored would come back stale.
          add_column('portal_role', 'String')
          add_column('portal_role_id', 'String', writable: true)
          # Owned by the integrations the contact was seen through; no endpoint
          # takes it.
          add_column('integration_user_ids', 'Json')
        end
      end
    end
  end
end
