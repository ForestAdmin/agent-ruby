module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module Context
        class ActionContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          include ForestAdminDatasourceToolkit

          attr_reader :filter, :used

          def initialize(collection, caller, form_value, filter, used = [], change_field = nil)
            super(collection, caller)
            @form_value = form_value
            @filter = filter
            @used = used
            @change_field = change_field
          end

          def field_changed?(field_name)
            @used << field_name

            @change_field == field_name
          end

          def form_value(key)
            @used << key

            @form_value[key]
          end

          def records(_fields = [])
            # Validations::ProjectionValidator.validate?(@real_collection, fields)

            @real_collection.list(@caller, @filter, [])
          end

          def record_ids
            composite_ids = composite_record_ids

            composite_ids.map { |id| id[0] }
          end

          def composite_record_ids
            projection = Components::Query::Projection.new.with_pks(@real_collection)
            records = records(projection)

            records.map { |record| Utils::Record.primary_keys(@real_collection, record) }
          end
        end
      end
    end
  end
end
