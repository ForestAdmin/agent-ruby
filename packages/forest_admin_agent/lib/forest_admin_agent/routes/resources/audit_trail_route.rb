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
        include AuditTrailWithholding

        # The caller's scope when the record is gone for good, nil otherwise — no scope in effect, or a record
        # still there and in scope. A scope can't be evaluated against a record that no longer exists, so its
        # history is served, but the values its rows captured while it existed still have to be tested against
        # that scope before being handed back.
        def assert_record_in_scope(context, collection, packed_id)
          return nil if scoped_record(context, collection, packed_id)

          # Nothing there: gone for good, since an out-of-scope record raised above. Without a scope in
          # effect this reads nil, which is the same answer.
          context.permissions.get_scope(collection)
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

        # The scope to withhold with: the caller's own, if the record was gone at either look at it.
        #
        # Both looks count, and neither can clear the other. The first is the only one that saw the record as
        # it was when the rows were chosen, so a replacement the second finds — an id freed by a delete and
        # taken by another record since — answers for itself, never for the life whose rows these are. The
        # second is the only one that can see a record deleted since, and it is where the 404 comes from when
        # that replacement is one this caller cannot read.
        def withholding_scope_for(context, collection, packed_id, gone_at_check)
          gone_since = scope_if_gone_since(context, collection, packed_id)

          gone_at_check || gone_since
        end

        # Second read of the record, once the rows are in hand, so the answer that decides the withholding is
        # never older than what it decides on. Skipped without a scope in effect — there is nothing to withhold
        # then, and nothing to ask. A record moved out of scope rather than deleted raises the 404 it would
        # raise for a request starting a moment later.
        def scope_if_gone_since(context, collection, packed_id)
          return nil if context.permissions.get_scope(collection).nil?

          assert_record_in_scope(context, collection, packed_id)
        end

        # Camelize only the top-level keys — the row `id` included, which the front uses as the tiebreaker when
        # merging pages ordered by (timestamp, id). Value hashes keep the keys they were stored with: a record's
        # own column names, or an action answer's camelCase Forest names.
        def serialize_record(record)
          record.to_h.transform_keys { |key| key.to_s.camelize(:lower) }
        end

        def store
          ::ForestAdminAgent::AuditTrail.store
        end

        # How to withhold the rows served for this id. A record gone at either look has all its rows tested
        # against the caller's scope. A live one in scope still has the rows filed before it took the id: a
        # delete frees an id, and a confirmed `create` marks where a record took one freed without a confirmed
        # delete — a primary-key move, or a delete that never confirmed. Those rows are another record's, which
        # the current one's scope says nothing about.
        def withholding_of(context, collection, packed_id, gone_at_check)
          gone_scope = withholding_scope_for(context, collection, packed_id, gone_at_check)
          return Withholding.new(collection, gone_scope, context.caller.timezone) if gone_scope

          scope = context.permissions.get_scope(collection)
          boundary = scope && store.life_boundary_of(collection: collection.name, record_id: packed_id)

          Withholding.new(collection, boundary && scope, context.caller.timezone, boundary)
        end

        def available_user(author)
          { id: author[:user_id], firstName: author[:user_first_name],
            lastName: author[:user_last_name], email: author[:user_email] }
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
