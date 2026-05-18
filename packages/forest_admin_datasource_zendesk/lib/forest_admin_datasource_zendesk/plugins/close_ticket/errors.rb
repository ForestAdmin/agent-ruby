module ForestAdminDatasourceZendesk
  module Plugins
    class CloseTicket
      # Decoding helpers for Zendesk's structured update-error payloads.
      module Errors
        module_function

        # Zendesk refuses any update on a closed ticket with this exact
        # wording on the `status` field — detected so we can swap the raw
        # stack for a clean message.
        ALREADY_CLOSED_DESCRIPTION = 'closed prevents ticket update'.freeze

        def already_closed?(error)
          invalid = unwrap_record_invalid(error)
          return false unless invalid

          status_errors = invalid.errors.is_a?(Hash) ? Array(invalid.errors['status']) : []
          status_errors.any? do |entry|
            entry.is_a?(Hash) && entry['description'].to_s.include?(ALREADY_CLOSED_DESCRIPTION)
          end
        end

        def unwrap_record_invalid(error)
          while error
            return error if error.is_a?(ZendeskAPI::Error::RecordInvalid)

            error = error.cause
          end
          nil
        end
      end
    end
  end
end
