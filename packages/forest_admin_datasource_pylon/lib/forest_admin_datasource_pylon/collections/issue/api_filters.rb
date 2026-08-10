module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      # The allow-list of `POST /issues/search`, transcribed from the API
      # reference: a field absent from this table cannot be filtered at all, and
      # an operator absent from a field's map is rejected by Pylon.
      #
      # It is the single source of truth for filtering — `define_schema` derives
      # every column's `filter_operators` from it, so the schema cannot
      # advertise a filter the translator would then refuse.
      module ApiFilters
        Operators = BaseCollection::Operators

        # `not_equal` is deliberately absent: the toolkit derives it from
        # `not_in`, so declaring it would only add a second spelling.
        EQUALITY = { Operators::EQUAL => 'equals',
                     Operators::IN => 'in',
                     Operators::NOT_IN => 'not_in' }.freeze

        PRESENCE = { Operators::PRESENT => 'is_set',
                     Operators::BLANK => 'is_unset' }.freeze

        # Declaring the bare comparisons rather than before/after is what lets
        # the toolkit rewrite Today / PreviousWeek / ... into a pair of bounds,
        # which is also why `time_range` never has to be emitted.
        TIME = { Operators::GREATER_THAN => 'time_is_after',
                 Operators::LESS_THAN => 'time_is_before' }.freeze

        # Pylon exposes a single substring operator, so both Forest spellings of
        # "contains" map onto it.
        FULL_TEXT = { Operators::CONTAINS => 'string_contains',
                      Operators::I_CONTAINS => 'string_contains',
                      Operators::NOT_CONTAINS => 'string_does_not_contain' }.freeze

        # `tags` holds a list: `contains` asks whether one tag belongs to it,
        # while `in` matches it against several candidates at once.
        MEMBERSHIP = { Operators::CONTAINS => 'contains',
                       Operators::NOT_CONTAINS => 'does_not_contain',
                       Operators::IN => 'in',
                       Operators::NOT_IN => 'not_in' }.freeze

        # `param` carries the read-to-filter renames: an issue is read with
        # `type` / `resolution_time` / `latest_message_time` but filtered on
        # `issue_type` / `resolved_at` / `latest_message_activity_at`.
        API_FILTERS = {
          'state' => { ops: EQUALITY },
          'type' => { param: 'issue_type', ops: EQUALITY.merge(PRESENCE) },
          'account_id' => { ops: EQUALITY.merge(PRESENCE) },
          'requester_id' => { ops: EQUALITY.merge(PRESENCE) },
          'assignee_id' => { ops: EQUALITY.merge(PRESENCE) },
          'team_id' => { ops: EQUALITY },
          'title' => { ops: FULL_TEXT },
          'body_html' => { ops: FULL_TEXT },
          'tags' => { ops: MEMBERSHIP },
          'created_at' => { ops: TIME },
          'updated_at' => { ops: TIME },
          'resolution_time' => { param: 'resolved_at', ops: TIME },
          'latest_message_time' => { param: 'latest_message_activity_at', ops: TIME }
        }.freeze

        # A custom field is filtered through its slug, so the operators come
        # from the column the integrator declared rather than from a table.
        CUSTOM_FIELD_OPS = EQUALITY.merge(PRESENCE).merge(TIME).merge(FULL_TEXT).freeze

        def self.forest_operators(field)
          API_FILTERS.dig(field, :ops)&.keys || []
        end

        def self.for_custom_field(schema)
          { ops: CUSTOM_FIELD_OPS.slice(*Array(schema&.filter_operators)) }
        end
      end
    end
  end
end
