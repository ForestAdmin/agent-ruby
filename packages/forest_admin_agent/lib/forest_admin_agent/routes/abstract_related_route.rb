module ForestAdminAgent
  module Routes
    class AbstractRelatedRoute < AbstractAuthenticatedRoute
      def build(args = {})
        super

        relation = @collection.fields[args[:params]['relation_name']]
        @child_collection = @datasource.collection(relation.foreign_collection)
      end
    end
  end
end
