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
          scoped_record(context, collection, packed_id)

          nil
        end

        # The record as it stands, read through the caller's permission scope. nil when it no longer exists
        # — a deleted record keeps its history readable, which is much of the point of an audit trail — and
        # a 404 when it does exist outside that scope.
        #
        # Authorizing and reading are the same query on purpose: a scoped check followed by an unscoped read
        # would hand back a row the check never covered, the moment the two drifted apart.
        def scoped_record(context, collection, packed_id, projection = nil)
          condition = ConditionTree::ConditionTreeFactory.match_records(
            collection, [Utils::Id.unpack_id(collection, packed_id, with_key: true)]
          )
          scope = context.permissions.get_scope(collection)
          in_scope = ConditionTree::ConditionTreeFactory.intersect([condition, scope])
          record = first_record(context, collection, in_scope, projection || key_projection(collection))

          return record if record
          # Nothing in scope: either gone for good, or someone else's record. Without a scope the query
          # above already answered the question.
          return nil if scope.nil? || first_record(context, collection, condition, key_projection(collection)).nil?

          raise Http::Exceptions::NotFoundError, 'Record does not exists'
        end

        # Camelize only the top-level keys — the row `id` included, which the front uses as the tiebreaker when
        # merging pages ordered by (timestamp, id). Value hashes keep the keys they were stored with: a record's
        # own column names, or an action answer's camelCase Forest names.
        def serialize_record(record)
          # `previous_record_id` stays out: it is how the agent follows a record across a rename, not something
          # the payload contract carries.
          record.to_h.except(:previous_record_id).transform_keys { |key| key.to_s.camelize(:lower) }
        end

        def store
          ::ForestAdminAgent::AuditTrail.store
        end

        # Every id this record has been filed under, newest first. Rows written before an update moved a
        # writable primary key stay under the id they were true of, so a history query that asked for the
        # current id alone would start at the rename and call that the whole story.
        #
        # ponytail: 10 hops is far more renaming than any record sees; the guard is against a cycle, not depth.
        MAX_RENAMES = 10

        def record_ids_history(collection, packed_id)
          ids = [packed_id]

          MAX_RENAMES.times do
            previous = store.previous_record_ids(collection: collection.name, record_id: ids.last)
            previous -= ids
            break if previous.empty?

            ids.concat(previous)
          end

          ids
        end

        # What the audit trail actually records: primary keys, so a state can be identified, plus the writable
        # columns. Reading read-only ones would hand them back at their present value inside an answer that
        # claims to describe a past instant.
        def audited_projection(collection)
          writable = collection.schema[:fields].select do |_name, field|
            field.type == 'Column' && !field.is_read_only
          end.keys

          Projection.new((ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection) + writable).uniq)
        end

        def key_projection(collection)
          Projection.new(ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection))
        end

        def first_record(context, collection, condition_tree, projection)
          collection.list(context.caller, Filter.new(condition_tree: condition_tree), projection).first
        end
      end
    end
  end
end
