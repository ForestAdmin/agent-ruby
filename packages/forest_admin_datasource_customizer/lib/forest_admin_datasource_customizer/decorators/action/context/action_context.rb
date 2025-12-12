module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module Context
        class ActionContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          include ForestAdminDatasourceToolkit

          attr_reader :filter, :used, :form_values

          def initialize(collection, caller, form_values, filter, used = [], change_field = nil)
            super(collection, caller)
            @form_values = form_values
            @filter = filter
            @used = used
            @change_field = change_field
          end

          def _filter=(value)
            @filter = value
          end

          def _used=(value)
            @used = value
          end

          def _form_values=(value)
            @form_values = value
          end

          def field_changed?(field_name)
            @used << field_name

            @change_field == field_name
          end

          def get_form_value(key)
            @used << key

            @form_values[key]
          end

          def get_records(fields = [])
            Validations::ProjectionValidator.validate?(@real_collection, fields)

            @real_collection.list(@caller, @filter, Components::Query::Projection.new)
          end

          def record_ids
            composite_ids = composite_record_ids

            composite_ids.map { |id| id[0] }
          end

          def composite_record_ids
            projection = Components::Query::Projection.new.with_pks(@real_collection)
            records = get_records(projection)

            records.map { |record| Utils::Record.primary_keys(@real_collection, record) }
          end

          alias get_record_ids record_ids
          alias get_composite_record_ids composite_record_ids
          alias has_field_changed field_changed?
          alias form_value get_form_value
        end
      end
    end
  end
end
