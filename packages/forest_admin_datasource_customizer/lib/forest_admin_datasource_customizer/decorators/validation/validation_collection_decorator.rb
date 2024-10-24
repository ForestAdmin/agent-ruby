module ForestAdminDatasourceCustomizer
  module Decorators
    module Validation
      class ValidationCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Validations
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :validation

        def initialize(child_collection, datasource)
          super
          @validation = {}
        end

        def add_validation(name, validation)
          FieldValidator.validate(self, name)

          field = @child_collection.schema[:fields][name]
          if field.nil? || field.type != 'Column'
            raise ForestException,
                  'Cannot add validators on a relation, use the foreign key instead'
          end
          raise ForestException, 'Cannot add validators on a readonly field' if field.is_read_only

          @validation[name] ||= []
          @validation[name].push(validation)
          mark_schema_as_dirty
        end

        def create(caller, data)
          data.each { |record| validate(record, caller.timezone, true) }
          child_collection.create(caller, data)
        end

        def update(caller, filter, patch)
          validate(patch, caller.timezone, false)
          child_collection.update(caller, filter, patch)
        end

        def refine_schema(child_schema)
          @validation.each do |name, rules|
            field = child_schema[:fields][name]
            field.validations = (field.validations || []).concat(rules)
            child_schema[:fields][name] = field
          end

          child_schema
        end

        private

        def validate(record, timezone, all_fields)
          @validation.each do |name, rules|
            next unless all_fields || record.key?(name)

            # When setting a field to nil, only the "Present" validator is relevant
            applicable_rules = record[name].nil? ? rules.select { |r| r[:operator] == Operators::PRESENT } : rules

            applicable_rules.each do |validator|
              raw_leaf = { field: name }.merge(validator)
              tree = ConditionTreeFactory.from_plain_object(raw_leaf)
              next if tree.match(record, self, timezone)

              message = "#{name} failed validation rule :"
              rule = if validator.key?(:value)
                       "#{validator[:operator]}(#{if validator[:value].is_a?(Array)
                                                    validator[:value].join(",")
                                                  else
                                                    validator[:value]
                                                  end})"
                     else
                       validator[:operator]
                     end

              raise ValidationError, "#{message} #{rule}"
            end
          end
        end
      end
    end
  end
end
