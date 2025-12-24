module ForestAdminDatasourceMongoid
  module Parser
    module Relation
      def get_polymorphic_types(relation_name)
        types = {}

        ObjectSpace.each_object(Class).each do |klass|
          next unless klass < Mongoid::Document

          if klass.relations.any? { |_, relation| relation.options[:as] == relation_name.to_sym }
            primary_key = klass.fields.keys.find { |key| klass.fields[key].options[:as] == :id } || :_id
            types[klass.name.gsub('::', '__')] = primary_key.to_s
          end
        end

        types
      end
    end
  end
end
