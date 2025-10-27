module ForestAdminDatasourceActiveRecord
  module Parser
    module Relation
      def associations(model, support_polymorphic_relations: false)
        model.reflect_on_all_associations.select do |association|
          is_valid_association = !get_class(association).nil? && !active_type?(get_class(association))
          if support_polymorphic_relations
            polymorphic?(association) || is_valid_association
          else
            !polymorphic?(association) && is_valid_association
          end
        end
      end

      def polymorphic?(association)
        (association.options.key?(:polymorphic) && association.options[:polymorphic]) ||
          association.inverse_of&.polymorphic?
      end

      def get_class(association)
        association.klass
      rescue StandardError
        nil
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

      def association_primary_key(association)
        association.options[:primary_key]&.to_s || association.association_primary_key
      end
    end
  end
end
