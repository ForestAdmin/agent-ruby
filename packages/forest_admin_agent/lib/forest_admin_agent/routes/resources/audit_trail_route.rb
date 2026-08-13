module ForestAdminAgent
  module Routes
    module Resources
      # Behaviour shared by every audit-trail route: they all take a packed record id straight from the
      # request, so the caller's permission scope has to be checked against that record before any
      # history is returned (`can?(:read, collection)` alone only proves access to the collection — a
      # role restricted to a subset of the records would otherwise read the history of any of them),
      # and they all serialize audit records the same way.
      module AuditTrailRoute
        include ForestAdminDatasourceToolkit::Components::Query

        def assert_record_in_scope(context, collection, packed_id)
          condition = ConditionTree::ConditionTreeFactory.match_records(
            collection, [Utils::Id.unpack_id(collection, packed_id, with_key: true)]
          )
          scope = context.permissions.get_scope(collection)

          return if any_record?(context, collection, ConditionTree::ConditionTreeFactory.intersect([condition, scope]))

          # Nothing in scope means the record is either outside it or gone for good. A deleted record
          # keeps its history readable — inspecting what was deleted is much of the point of an audit
          # trail — so only a record that still exists outside the scope is refused. Without a scope
          # the first query already answered the question.
          return if scope.nil? || !any_record?(context, collection, condition)

          raise Http::Exceptions::NotFoundError, 'Record does not exists'
        end

        # Camelize only the top-level keys; previous/new value hashes keep the record's own column names.
        def serialize_record(record)
          record.to_h.transform_keys { |key| key.to_s.camelize(:lower) }
        end

        def store
          ::ForestAdminAgent::AuditTrail.store
        end

        # The audited columns as they stand now — the starting point of a state reconstruction. No scope in
        # the filter: the caller was already authorized against it, and a record that is simply gone has to
        # come back as nil so the history can restore it.
        def current_record(context, collection, packed_id)
          columns = collection.schema[:fields].select { |_name, field| field.type == 'Column' }.keys
          condition = ConditionTree::ConditionTreeFactory.match_records(
            collection, [Utils::Id.unpack_id(collection, packed_id, with_key: true)]
          )

          collection.list(context.caller, Filter.new(condition_tree: condition), Projection.new(columns)).first
        end

        def any_record?(context, collection, condition_tree)
          collection.list(
            context.caller,
            Filter.new(condition_tree: condition_tree),
            Projection.new(ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection))
          ).any?
        end
      end
    end
  end
end
