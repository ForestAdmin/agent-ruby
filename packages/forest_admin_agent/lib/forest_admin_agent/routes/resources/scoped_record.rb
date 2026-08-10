module ForestAdminAgent
  module Routes
    module Resources
      # Shared by the audit-trail routes: they take a packed record id straight from the request, so
      # the caller's permission scope has to be checked against that record before any history is
      # returned. `can?(:read, collection)` alone only proves access to the collection — a role
      # restricted to a subset of the records would otherwise read the history of any of them.
      module ScopedRecord
        include ForestAdminDatasourceToolkit::Components::Query

        def assert_record_in_scope(context, collection, packed_id)
          scope = context.permissions.get_scope(collection)
          record = ConditionTree::ConditionTreeFactory.match_records(
            collection, [Utils::Id.unpack_id(collection, packed_id, with_key: true)]
          )
          filter = Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([record, scope])
          )
          projection = Projection.new(ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection))

          return unless collection.list(context.caller, filter, projection).empty?

          raise Http::Exceptions::NotFoundError, 'Record does not exists'
        end
      end
    end
  end
end
