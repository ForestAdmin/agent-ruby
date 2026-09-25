module ForestAdminAgent
  module Routes
    module Resources
      # Blanks the captured values a caller's record-level scope does not cover, keeping the rows themselves:
      # that something happened, by whom and when, stays visible either way. Shared by every route that serves
      # captured values — the per-record history, the state reconstruction and the two correlation routes —
      # since a rule only one of them applies is one lookup away from being no rule at all.
      module AuditTrailWithholding
        # Everything a withholding decision needs, and nothing a request context would drag along: the
        # collection the rows belong to, the scope to test them against, and the timezone its date
        # comparisons read in.
        Withholding = Struct.new(:collection, :scope, :timezone)

        # A record that is gone for good bypasses the scope check — there is nothing left to check it against
        # — but its rows still carry the column values captured while it existed. When those values would
        # themselves have failed the caller's scope, withhold them; the row itself stays visible either way,
        # so that it happened, by whom and when still reads.
        def withhold_out_of_scope_values(entries, withholding)
          return entries if withholding.scope.nil?

          entries.map { |entry| withhold(entry, withholding) }
        end

        def withhold(entry, withholding)
          case entry.operation
          # `delete`'s previous_values and `create`'s new_values both capture every writable column.
          when 'delete'
            in_scope?(entry.previous_values, entry.record_id, withholding) ? entry : blank(entry, :previous_values)
          when 'create'
            in_scope?(entry.new_values, entry.record_id, withholding) ? entry : blank(entry, :new_values)
          when 'update'
            withhold_each_side(entry, withholding)
          # `action`/`action_failed` rows hold a submitted form and a result summary, not column values, so
          # the scope doesn't apply to them.
          else
            entry
          end
        end

        # An update's two sides are a partial diff, so each is tested against its own values: a diff that never
        # carried the scoped column answers for neither and is withheld by `in_scope?` anyway. Gating the sides
        # separately releases the ones that can be proven in scope — "it used to be X" can't escape through a
        # row whose new value is out of scope, since that side is tested on its own.
        def withhold_each_side(entry, withholding)
          # An update that moved a writable primary key files its row under the id the record ended up with,
          # and keeps the one it had on `previous_record_id`. Each side is tested against the id it was true
          # of, or the new state's id would decide whether the old state is in scope.
          before = entry.previous_record_id || entry.record_id
          kept = in_scope?(entry.previous_values, before, withholding) ? entry : blank(entry, :previous_values)

          in_scope?(kept.new_values, after_id(kept), withholding) ? kept : blank(kept, :new_values)
        end

        # A pending row is filed under the id the record had *before* the write, since the write may not have
        # landed: it says nothing about the state the update was moving to, so the new side gets no id to fill
        # from and falls back on what it captured itself.
        def after_id(entry)
          entry.status == ::ForestAdminAgent::AuditTrail::Recording::PENDING ? nil : entry.record_id
        end

        # Only a snapshot that answers every field the scope asks about, with what was really stored, is worth
        # matching. The capture keeps the writable columns, so a scope on anything else — a read-only column, a
        # relation — reads as nil there and would answer for a value the row never held: `status != 'private'`
        # would match, and an ordered operator would raise on the nil. A redacted value answers no better.
        def in_scope?(values, packed_id, withholding, id_answers_for_keys: true)
          snapshot = answerable_snapshot(values, packed_id, withholding.collection,
                                         id_answers_for_keys: id_answers_for_keys)
          return false unless withholding.scope.projection.all? { |field| snapshot.key?(field) }

          withholding.scope.match(snapshot, withholding.collection, withholding.timezone)
        rescue StandardError => e
          # Key presence is not answerability: a column captured as nil has its key, and an ordered operator
          # raises on it. Uncaught that would fail the whole page, and only for the callers a scope applies
          # to. One withheld row is the smaller loss, and the same answer the field would have got had it
          # been missing outright.
          Facades::Container.logger&.log('Warn', "[ForestAdmin] Audit row not scope-checkable: #{e.message}")

          false
        end

        # What this side of the row can answer about. A redacted value answers nothing, so it is dropped rather
        # than matched against the placeholder — leaving the field unanswered, which withholds. The packed id
        # then fills in the primary keys: a read-only one never lands in the snapshot at all, and a writable one
        # the trail redacts was just dropped, while the id the row was filed under proves what the key was.
        # It only fills what the snapshot cannot answer: on the side of a row that captured the key itself,
        # that value is the one that was true there.
        #
        # `id_answers_for_keys: false` keeps the id off the keys the trail redacted, for a caller holding an id
        # that may not be the one its values were true under — a state reconstruction, which can sit on the far
        # side of a primary-key move it cannot see. A key never captured at all is still filled: read-only, so
        # it cannot have moved.
        def answerable_snapshot(values, packed_id, collection, id_answers_for_keys: true)
          captured = values || {}
          redacted = captured.select { |_, value| value == ::ForestAdminAgent::AuditTrail::Recording::REDACTED }.keys
          answered = captured.except(*redacted)
          return answered if packed_id.nil?

          decoded = decoded_keys(collection, packed_id)
          decoded = decoded.except(*redacted) unless id_answers_for_keys

          decoded.merge(answered)
        end

        def decoded_keys(collection, packed_id)
          Utils::Id.unpack_id(collection, packed_id, with_key: true)
        rescue StandardError => e
          # An id written under a primary key of another shape costs the keys it would have filled, and
          # nothing else: the snapshot still answers for the columns it captured, so a scope that never
          # asks about the id is unaffected.
          Facades::Container.logger&.log('Warn', "[ForestAdmin] Audit row id not decodable: #{e.message}")

          {}
        end

        def blank(entry, *fields)
          entry.dup.tap { |copy| fields.each { |field| copy[field] = {} } }
        end
      end
    end
  end
end
