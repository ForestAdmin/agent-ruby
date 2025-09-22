module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module Context
        class ActionContextSingle < ActionContext
          include ForestAdminDatasourceToolkit

          def get_record(fields = [])
            get_records(fields)[0]
          end

          def record_id
            composite_record_id[0]
          end

          def composite_record_id
            composite_record_ids[0]
          end

          alias get_record_id record_id
          alias get_composite_record_id composite_record_id
        end
      end
    end
  end
end
