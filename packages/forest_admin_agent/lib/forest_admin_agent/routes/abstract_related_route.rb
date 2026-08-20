module ForestAdminAgent
  module Routes
    class AbstractRelatedRoute < AbstractAuthenticatedRoute
      def build(args = {})
        context = super

        relation = context.collection.schema[:fields][args[:params]['relation_name']]
        context.child_collection = if relation.type == 'PolymorphicManyToOne'
                                     if (type = args.dig(:params, 'data', 'type'))
                                       context.datasource.get_collection(type)
                                     end
                                   else
                                     context.datasource.get_collection(relation.foreign_collection)
                                   end

        context
      end
    end
  end
end
