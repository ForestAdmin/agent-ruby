module ForestAdminDatasourceZendesk
  module Plugins
    class CloseTicket
      module Messages
        module_function

        def success(succeeded, already_closed, failed, status)
          [succeeded_phrase(succeeded, status), already_closed_phrase(already_closed),
           failed_phrase(failed)].compact.join(' ')
        end

        def error(failed, status)
          verb = status == 'closed' ? 'close' : 'mark as solved'
          return "Failed to #{verb} ticket ##{failed.first.first}: #{failed.first.last}" if failed.size == 1

          "Failed to #{verb} all #{failed.size} tickets. First error: #{failed.first.last}"
        end

        def succeeded_phrase(succeeded, status)
          return nil if succeeded.empty?

          verb = status == 'closed' ? 'closed' : 'marked as solved'
          succeeded.size == 1 ? "Ticket ##{succeeded.first} #{verb}." : "#{succeeded.size} tickets #{verb}."
        end

        def already_closed_phrase(already_closed)
          return nil if already_closed.empty?
          return "Ticket ##{already_closed.first} was already closed." if already_closed.size == 1

          "#{already_closed.size} tickets were already closed: #{already_closed.join(", ")}."
        end

        def failed_phrase(failed)
          return nil if failed.empty?

          "#{failed.size} failed: #{failed.map(&:first).join(", ")}."
        end
      end
    end
  end
end
