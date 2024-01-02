module ForestAdminDatasourceCustomizer
  module Decorators
    module Actions
      module Context
        class ActionContextSingle < ActionContext
          include ForestAdminDatasourceToolkit

          def record(fields = [])
            records(fields)[0]
          end

          def record_id
            composite_record_id[0]
          end

          def composite_record_id
            composite_record_ids[0]
          end
        end
      end
    end
  end
end
