module ForestAdminDatasourcePylon
  module Query
    # The operator maps the Pylon search endpoints share. A map spells each
    # Forest operator as the Pylon operator honouring it; a collection's
    # `API_FILTERS` table then assembles, field by field, the maps its endpoint
    # accepts according to the API reference.
    #
    # Sharing the maps is what keeps those tables readable as the allow-lists
    # they transcribe, and keeps one wire spelling from being fixed in one
    # collection and left wrong in the next.
    module OperatorMaps
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

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

      # Pylon exposes a single substring operator and documents no case
      # semantics for it, so both Forest spellings map onto that one operator --
      # or the UI would offer a case-sensitive "contains" and a case-insensitive
      # one behaving identically.
      SUBSTRING = { Operators::CONTAINS => 'string_contains',
                    Operators::I_CONTAINS => 'string_contains' }.freeze

      # The same, for the endpoints that also accept the negation. A field
      # filtered through SUBSTRING alone must not advertise it: Pylon rejects
      # `string_does_not_contain` where it is not documented.
      FULL_TEXT = SUBSTRING.merge(Operators::NOT_CONTAINS => 'string_does_not_contain',
                                  Operators::NOT_I_CONTAINS => 'string_does_not_contain').freeze

      # A list-valued field -- `tags`, `domains`: `contains` asks whether one
      # value belongs to it, while `in` matches it against several candidates at
      # once.
      MEMBERSHIP = { Operators::CONTAINS => 'contains',
                     Operators::NOT_CONTAINS => 'does_not_contain',
                     Operators::IN => 'in',
                     Operators::NOT_IN => 'not_in' }.freeze

      # A custom field is filtered through its slug, so its operators come from
      # the column the integrator declared rather than from a table; every
      # search endpoint accepts this same set on one.
      CUSTOM_FIELD_OPS = EQUALITY.merge(PRESENCE).merge(TIME).merge(FULL_TEXT).freeze

      # Extended by a collection's `ApiFilters` module, whose `API_FILTERS` is
      # the single source of truth for what its endpoint filters: the schema
      # derives every column's `filter_operators` from it, so it cannot
      # advertise a filter the translator would then refuse.
      module Table
        def forest_operators(field)
          self::API_FILTERS.dig(field, :ops)&.keys || []
        end

        def for_custom_field(schema)
          { ops: CUSTOM_FIELD_OPS.slice(*Array(schema&.filter_operators)) }
        end
      end
    end
  end
end
