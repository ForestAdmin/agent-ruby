module ForestAdminDatasourceActiveRecord
  module Parser
    module Relation
      def associations(model)
        model.reflect_on_all_associations.select do |association|
          polymorphic?(association) ? true : !active_type?(association.klass)
        end
      end

      def polymorphic?(association)
        association.options[:polymorphic]
      end

      # NOTICE: Ignores ActiveType::Object association during introspection and interactions.
      #         See the gem documentation: https://github.com/makandra/active_type
      def active_type?(model)
        Object.const_defined?('ActiveType::Object') && model < ActiveType::Object
      end

      def get_polymorphic_types(relation)
        types = {}
        @datasource.models.each do |model|
          unless model.reflect_on_all_associations.none? { |assoc| assoc.options[:as] == relation.name.to_sym }
            types[format_model_name(model.name)] = model.primary_key
          end
        end

        types
      end
    end
  end
end
