module ForestAdminDatasourceMongoid
  module Parser
    module Relation
      # TODO

      # def associations(model, support_polymorphic_relations: false)
      #   model.reflect_on_all_associations.select do |association|
      #     is_valid_association = !get_class(association).nil? && !active_type?(get_class(association))
      #     if support_polymorphic_relations
      #       polymorphic?(association) ? true : is_valid_association
      #     else
      #       !polymorphic?(association) && is_valid_association
      #     end
      #   end
      # end
      #
      # def polymorphic?(association)
      #   (association.options.key?(:polymorphic) && association.options[:polymorphic]) ||
      #     association.inverse_of&.polymorphic?
      # end
      #
      # def get_class(association)
      #   association.klass
      # rescue StandardError
      #   nil
      # end
      #
      # # NOTICE: Ignores ActiveType::Object association during introspection and interactions.
      # #         See the gem documentation: https://github.com/makandra/active_type
      # def active_type?(model)
      #   Object.const_defined?('ActiveType::Object') && model < ActiveType::Object
      # end
      #
      # def get_polymorphic_types(relation)
      #   types = {}
      #   @datasource.models.each do |model|
      #     unless model.reflect_on_all_associations.none? { |assoc| assoc.options[:as] == relation.name.to_sym }
      #       types[format_model_name(model.name)] = model.primary_key
      #     end
      #   end
      #
      #   types
      # end

      # def get_polymorphic_types(relation_name)
      #   ObjectSpace.each_object(Class).select do |klass|
      #     next unless klass < Mongoid::Document
      #     klass.relations.any? do |_rel_name, relation|
      #       relation.options[:as].to_s == relation_name.to_s
      #     end
      #   end.map(&:name)
      # end

      def get_polymorphic_types(relation_name)
        types = {}

        ObjectSpace.each_object(Class).select { |klass| klass < Mongoid::Document }.each do |model|
          if model.relations.any? { |_, relation| relation.options[:as] == relation_name.to_sym }
            primary_key = model.fields.keys.find { |key| model.fields[key].options[:as] == :id } || :_id
            types[model.name] = primary_key
          end
        end

        types
      end
    end
  end
end
