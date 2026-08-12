module ForestAdminDatasourcePylon
  module Collections
    class Contact < CursorCollection
      # The allow-list of `POST /contacts/search`, transcribed from the API
      # reference: a field absent from this table cannot be filtered at all, and
      # an operator absent from a field's map is rejected by Pylon.
      #
      # It is the single source of truth for filtering — `define_schema` derives
      # every column's `filter_operators` from it, so the schema cannot
      # advertise a filter the translator would then refuse.
      module ApiFilters
        Maps = Query::OperatorMaps

        extend Maps::Table

        CUSTOM_FIELD_OPS = Maps::CUSTOM_FIELD_OPS

        # `id` is filtered server-side here, which is what spares this
        # collection the primary-key short-circuit Issue needs.
        #
        # `name` and `email` get SUBSTRING rather than FULL_TEXT: the endpoint
        # accepts `string_contains` but no negation of it. `email` filters the
        # primary address only, not the `emails` list.
        #
        # The contacts search offers nothing else: no presence check, no
        # filter on the phone numbers, the portal role or the external ids.
        API_FILTERS = {
          'id' => { ops: Maps::EQUALITY },
          'name' => { ops: Maps::EQUALITY.merge(Maps::SUBSTRING) },
          'email' => { ops: Maps::EQUALITY.merge(Maps::SUBSTRING) },
          'account_id' => { ops: Maps::EQUALITY }
        }.freeze
      end
    end
  end
end
