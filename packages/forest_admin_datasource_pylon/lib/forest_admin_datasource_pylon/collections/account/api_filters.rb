module ForestAdminDatasourcePylon
  module Collections
    class Account < CursorCollection
      # The allow-list of `POST /accounts/search`, transcribed from the API
      # reference: a field absent from this table cannot be filtered at all, and
      # an operator absent from a field's map is rejected by Pylon.
      #
      # It is the single source of truth for filtering — `define_schema` derives
      # every column's `filter_operators` from it, so this collection declares no
      # filter the translator would then refuse; the absence family the agent
      # derives on top of it is the exception `Query::OperatorMaps::Table`
      # describes.
      module ApiFilters
        Maps = Query::OperatorMaps

        extend Maps::Table

        CUSTOM_FIELD_OPS = Maps::CUSTOM_FIELD_OPS

        # `id` is filtered server-side here, which is what spares this
        # collection the primary-key short-circuit Issue needs.
        #
        # `name` gets SUBSTRING rather than FULL_TEXT: the endpoint accepts
        # `string_contains` but no negation of it. `external_ids` is left out
        # entirely although the endpoint filters it — the API matches the bare
        # external-id strings while the column shows `{external_id, label}`
        # objects, so the filter would run on something the operator cannot see.
        # The account read endpoint accepts an external id in place of the
        # primary key, which is the way to reach a record by one.
        #
        # No time field is filterable: `created_at`, `updated_at` and
        # `latest_customer_activity_time` are absent from the allow-list.
        API_FILTERS = {
          'id' => { ops: Maps::EQUALITY },
          'name' => { ops: Maps::EQUALITY.merge(Maps::SUBSTRING) },
          'domains' => { ops: Maps::MEMBERSHIP },
          'tags' => { ops: Maps::MEMBERSHIP },
          'owner_id' => { ops: Maps::EQUALITY.merge(Maps::PRESENCE) }
        }.freeze
      end
    end
  end
end
