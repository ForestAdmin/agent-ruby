module ForestAdminDatasourceIntercom
  module Query
    # Read by both the schema and the translator, so a column never advertises an operator the translator
    # refuses. Which operators an endpoint accepts per field lives in `search_fields.yml`.
    module OperatorTable
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

      EQUALITY = { Operators::EQUAL => '=', Operators::NOT_EQUAL => '!=',
                   Operators::IN => 'IN', Operators::NOT_IN => 'NIN' }.freeze

      # `contains` and `i_contains` both map to `~`, Intercom's only substring operator. `not_i_contains` is
      # absent: the toolkit's `Rules` rejects it on a String column (PRD-989).
      SUBSTRING = { Operators::CONTAINS => '~', Operators::I_CONTAINS => '~',
                    Operators::NOT_CONTAINS => '!~',
                    Operators::STARTS_WITH => '^', Operators::ENDS_WITH => '$' }.freeze

      BOUNDS = { Operators::GREATER_THAN => '>', Operators::LESS_THAN => '<' }.freeze

      # Dates publish only the two bounds although both endpoints accept `=`, `!=`, `>=`, `<=` (measured):
      # declaring `equal` makes the toolkit republish `in`, which its validator refuses (PRD-989). The toolkit
      # still derives `today`, `past`, `previous_*` and the rest from the two bounds.
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
