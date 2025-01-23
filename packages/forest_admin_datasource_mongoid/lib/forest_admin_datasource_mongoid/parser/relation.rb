module ForestAdminDatasourceMongoid
  module Parser
    module Relation
      def get_polymorphic_types(relation_name)
        types = {}

        ObjectSpace.each_object(Class).select { |klass| klass < Mongoid::Document }.each do |model|
          if model.relations.any? { |_, relation| relation.options[:as] == relation_name.to_sym }
            primary_key = model.fields.keys.find { |key| model.fields[key].options[:as] == :id } || :_id
            types[format_model_name(model.name)] = primary_key.to_s
          end
        end

        types
      end
    end
  end
end
