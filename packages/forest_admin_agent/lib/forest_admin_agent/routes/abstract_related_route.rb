module ForestAdminAgent
  module Routes
    class AbstractRelatedRoute < AbstractAuthenticatedRoute
      def build(args = {})
        super

        relation = @collection.schema[:fields][args[:params]['relation_name']]
        @child_collection = @datasource.get_collection(relation.foreign_collection)
      end
    end
  end
end
