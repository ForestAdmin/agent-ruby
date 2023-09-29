module ForestAdminDatasourceActiveRecord
  module Parser
    module Relation
      def associations(model)
        model.reflect_on_all_associations.select do |association|
          !polymorphic?(association) && !active_type?(association.klass)
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
    end
  end
end
