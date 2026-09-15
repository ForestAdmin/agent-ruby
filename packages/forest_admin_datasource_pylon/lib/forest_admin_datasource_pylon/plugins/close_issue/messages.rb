module ForestAdminDatasourcePylon
  module Plugins
    class CloseIssue
      # What the operator reads once the batch ran. Every id that failed is
      # named: an action reporting a plain success over a batch it only half
      # applied is the one thing the panel cannot recover from.
      module Messages
        module_function

        def success(succeeded, failed, state)
          [succeeded_phrase(succeeded, state), failed_phrase(failed)].compact.join(' ')
        end

        def error(failed, state)
          return "Failed to #{verb(state)} issue #{failed.first.first}: #{failed.first.last}" if failed.size == 1

          "Failed to #{verb(state)} all #{failed.size} issues. First error: #{failed.first.last}"
        end

        # Worded around the selection rather than around the run: what the
        # operator can act on is how many issues they picked, and the cap is
        # named so the next attempt is a size they can aim for.
        def too_many(count, state)
          "This selection names #{count} Pylon issues, more than the #{CloseIssue::MAX_TARGETS} one run of " \
            'this action covers: Pylon takes one request per issue, and a run stopping halfway would leave ' \
            "part of the selection #{past_verb(state)} without naming which part. Select fewer issues, and " \
            'run the action again on the rest.'
        end

        def no_target(field)
          return 'No Pylon issue selected.' if field.nil?

          "No Pylon issue id found in '#{field}'."
        end

        def succeeded_phrase(succeeded, state)
          return nil if succeeded.empty?

          return "Issue #{succeeded.first} #{past_verb(state)}." if succeeded.size == 1

          "#{succeeded.size} issues #{past_verb(state)}."
        end

        def failed_phrase(failed)
          return nil if failed.empty?

          "#{failed.size} failed: #{failed.map(&:first).join(", ")}."
        end

        # A custom status is named as it is, where the state every organization
        # has reads as the verb an operator used to fire the action.
        def verb(state)
          state == IssueEnums::CLOSED_STATE ? 'close' : "move to #{state}"
        end

        def past_verb(state)
          state == IssueEnums::CLOSED_STATE ? 'closed' : "moved to #{state}"
        end
      end
    end
  end
end
