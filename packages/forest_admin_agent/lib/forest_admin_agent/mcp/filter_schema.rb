module ForestAdminAgent
  module Mcp
    class FilterSchema
      OPERATORS = %w[
        Equal
        NotEqual
        LessThan
        GreaterThan
        LessThanOrEqual
        GreaterThanOrEqual
        Match
        NotContains
        NotIContains
        LongerThan
        ShorterThan
        IncludesAll
        IncludesNone
        Today
        Yesterday
        PreviousMonth
        PreviousQuarter
        PreviousWeek
        PreviousYear
        PreviousMonthToDate
        PreviousQuarterToDate
        PreviousWeekToDate
        PreviousXDaysToDate
        PreviousXDays
        PreviousYearToDate
        Present
        Blank
        Missing
        In
        NotIn
        StartsWith
        EndsWith
        Contains
        IStartsWith
        IEndsWith
        IContains
        Like
        ILike
        Before
        After
        AfterXHoursAgo
        BeforeXHoursAgo
        Future
        Past
      ].freeze

      AGGREGATORS = %w[And Or].freeze

      def self.json_schema
        {
          oneOf: [
            leaf_schema,
            branch_schema
          ]
        }
      end

      def self.leaf_schema
        {
          type: 'object',
          properties: {
            field: { type: 'string' },
            operator: { type: 'string', enum: OPERATORS },
            value: {}
          },
          required: %w[field operator]
        }
      end

      def self.branch_schema
        {
          type: 'object',
          properties: {
            aggregator: { type: 'string', enum: AGGREGATORS },
            conditions: {
              type: 'array',
              items: { '$ref': '#' }
            }
          },
          required: %w[aggregator conditions]
        }
      end
    end
  end
end
