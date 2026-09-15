module ForestAdminDatasourceIntercom
  module Query
    # How a Forest operator is spelled in Intercom's search DSL, per kind of
    # field. Two things read this table and they must never disagree: the schema,
    # which publishes a column's `filter_operators`, and the translator, which
    # writes the filter. Both go through `forest_operators` and
    # `intercom_operator`, so a column cannot advertise a filter the translator
    # would then refuse.
    #
    # What an endpoint really accepts on a given field is not here -- that is
    # `search_fields.yml`, measured. This is only the spelling, and the set is
    # narrowed by the table before anything is published.
    module OperatorTable
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

      EQUALITY = { Operators::EQUAL => '=', Operators::NOT_EQUAL => '!=',
                   Operators::IN => 'IN', Operators::NOT_IN => 'NIN' }.freeze

      # `contains` and `i_contains` both land on `~`: Intercom documents one
      # substring operator and no case semantics for it, and the frontend sends
      # either spelling depending on the column. Declaring one alone would leave
      # the other refused at read time on a field Intercom does filter.
      #
      # `not_i_contains` is deliberately absent although Intercom would answer it
      # the same way as `not_contains`: the toolkit's own `Rules` does not allow
      # it on a String column, so publishing it would put a filter in the
      # interface that the agent rejects before this datasource is ever reached
      # -- the failure PRD-989 describes.
      SUBSTRING = { Operators::CONTAINS => '~', Operators::I_CONTAINS => '~',
                    Operators::NOT_CONTAINS => '!~',
                    Operators::STARTS_WITH => '^', Operators::ENDS_WITH => '$' }.freeze

      BOUNDS = { Operators::GREATER_THAN => '>', Operators::LESS_THAN => '<' }.freeze

      # A date field carries the two bounds and nothing else, even where the
      # endpoint accepts `=`, `!=`, `>=` and `<=` -- measured, it does on both
      # search endpoints. The reason is on the agent's side: declaring `equal` on
      # a Date column makes the toolkit republish `in`, which its own validator
      # then refuses (PRD-989), so the interface would offer a date filter
      # answered by a 400 having nothing to do with Intercom.
      #
      # Nothing is lost that an operator can see. From the two bounds the toolkit
      # derives `before`, `after`, `today`, `yesterday`, `past`, `future` and the
      # whole `previous_*` family -- twenty operators, all rewritten into a pair
      # of bounds before they reach here. What stays out is an equality on an
      # instant, which day-granular filtering could not honour anyway.
      MAPS = {
        'string' => EQUALITY,
        'boolean' => EQUALITY,
        'number' => EQUALITY.merge(BOUNDS),
        'text' => EQUALITY.merge(SUBSTRING),
        'date' => BOUNDS
      }.freeze

      # The operators that take a list rather than a value, on the wire.
      LIST_OPERATORS = %w[IN NIN].freeze

      class << self
        def types = MAPS.keys

        # What the column publishes: the Forest operators whose Intercom spelling
        # this endpoint accepts on this field, and no other.
        def forest_operators(field)
          MAPS.fetch(field.type).select { |_, spelling| field.operators.include?(spelling) }.keys
        end

        # nil when the endpoint does not accept that operator on that field,
        # which the translator turns into a refusal naming what it does accept.
        def intercom_operator(field, forest_operator)
          spelling = MAPS.fetch(field.type)[forest_operator]

          spelling if spelling && field.operators.include?(spelling)
        end

        def list_operator?(spelling) = LIST_OPERATORS.include?(spelling)
      end
    end
  end
end
