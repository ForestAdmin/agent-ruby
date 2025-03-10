module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      class ConditionGenerator
        include Utils::Schema

        FOREST_RECORD_DOES_NOT_EXIST = 'FOREST_RECORD_DOES_NOT_EXIST'.freeze

        def self.tag_record_if_not_exist(field, then_expr)
          if_missing(field, then_expr, { FOREST_RECORD_DOES_NOT_EXIST => true })
        end

        def self.tag_record_if_not_exist_by_value(field, then_expr)
          if_missing(field, then_expr, FOREST_RECORD_DOES_NOT_EXIST)
        end

        def self.if_missing(field, then_expr, else_expr)
          {
            '$cond' => {
              'if' => { '$and' => [{ '$ne' => [{ '$type' => "$#{field}" }, 'missing'] },
                                   { '$ne' => ["$#{field}", nil] }] },
              'then' => then_expr,
              'else' => else_expr
            }
          }
        end
      end
    end
  end
end
