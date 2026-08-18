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

      # MISSING is mapped as well although Pylon spells absence one way only:
      # the toolkit rewrites it into `equal nil` when it is left out, which the
      # translator cannot express, so a field the API does check for absence
      # would refuse the very filter it can answer.
      PRESENCE = { Operators::PRESENT => 'is_set',
                   Operators::BLANK => 'is_unset',
                   Operators::MISSING => 'is_unset' }.freeze

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

      # A list-valued field -- `tags`, `domains`: `in` matches it against
      # several candidates at once.
      #
      # Pylon also accepts `contains` / `does_not_contain` on such a field, and
      # they are deliberately left out: the columns are typed `Json`, the only
      # type the toolkit has for a list, and `Rules` allows a Json column the
      # base and array operators alone. A declared `contains` would be refused
      # by `ConditionTreeValidator` on the way in -- "the given operator
      # 'contains' is not allowed with the columnType schema: 'Json'" -- so the
      # UI would offer a filter that errors instead of one Pylon answers.
      # Typing the columns `['String']` is not the way out either: no branch of
      # `get_allowed_operators_for_column_type` reads an array type, and the
      # validator raises a NoMethodError on it. Reaching those two operators
      # takes a toolkit change, which is not this datasource's to make here.
      MEMBERSHIP = { Operators::IN => 'in',
                     Operators::NOT_IN => 'not_in' }.freeze

      # A custom field is filtered through its slug, so its operators come from
      # the column the integrator declared rather than from a table; every
      # search endpoint accepts this same set on one.
      CUSTOM_FIELD_OPS = EQUALITY.merge(PRESENCE).merge(TIME).merge(FULL_TEXT).freeze

      # Extended by a collection's `ApiFilters` module, whose `API_FILTERS` is
      # the single source of truth for what its endpoint filters: the schema
      # derives every column's `filter_operators` from it, so no collection
      # declares a filter the translator would then refuse.
      #
      # One family escapes those tables. The agent derives `present`, `blank` and
      # `missing` from an equality or a membership filter, above the datasource,
      # and rewrites them into a comparison with an empty value. Only a field
      # carrying PRESENCE can answer one -- Pylon matches an absent value through
      # `is_set` / `is_unset` alone -- so on every other field the translator
      # refuses the rewritten condition and names the filter to change, rather
      # than sending a comparison Pylon would answer as if the empty value were
      # a value of its own.
      module Table
        def forest_operators(field)
          self::API_FILTERS.dig(field, :ops)&.keys || []
        end

        # Read off the extending module rather than off this one, so the
        # `CUSTOM_FIELD_OPS` a collection declares is the single source both
        # this spelling and `allowed_custom_field_operators` come from: an
        # endpoint accepting less on a custom field narrows one constant.
        def for_custom_field(schema)
          { ops: self::CUSTOM_FIELD_OPS.slice(*Array(schema&.filter_operators)) }
        end
      end

      # The table of a collection whose endpoint filters nothing server-side: no
      # field, and no operator on a custom field either. It is the default of
      # `BaseCollection#filter_table`, so a collection read whole and filtered
      # in memory needs no table of its own.
      module EmptyTable
        extend Table

        API_FILTERS      = {}.freeze
        CUSTOM_FIELD_OPS = {}.freeze
      end
    end
  end
end
