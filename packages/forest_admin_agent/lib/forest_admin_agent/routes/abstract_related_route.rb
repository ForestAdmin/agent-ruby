module ForestAdminAgent
  module Routes
    class AbstractRelatedRoute < AbstractAuthenticatedRoute
      def build(args = {})
        context = super

        relation = context.collection.schema[:fields][args[:params]['relation_name']]
        # Use collection's datasource (decorated) to resolve renamed collections
        datasource = context.collection.datasource
        context.child_collection = if relation.type == 'PolymorphicManyToOne' && args[:params]['data']
                                     datasource.get_collection(args[:params]['data']['type'])
                                   elsif relation.type == 'PolymorphicManyToOne'
                                     # For polymorphic with nil data (dissociation), use first foreign collection
                                     datasource.get_collection(relation.foreign_collections.first)
                                   else
                                     datasource.get_collection(relation.foreign_collection)
                                   end

        context
      end
    end
  end
end
