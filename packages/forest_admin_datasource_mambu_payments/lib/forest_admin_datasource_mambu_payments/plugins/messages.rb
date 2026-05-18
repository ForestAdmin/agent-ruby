module ForestAdminDatasourceMambuPayments
  module Plugins
    module Messages
      module_function

      def success(succeeded, failed, noun:, verb_past:)
        [succeeded_phrase(succeeded, noun, verb_past), failed_phrase(failed, noun)].compact.join(' ')
      end

      def all_failed(failed, noun:, verb:)
        return "Failed to #{verb} #{noun} ##{failed.first.first}: #{failed.first.last}" if failed.size == 1

        "Failed to #{verb} all #{failed.size} #{noun}s. First error: #{failed.first.last}"
      end

      def succeeded_phrase(succeeded, noun, verb_past)
        return nil if succeeded.empty?
        return "#{noun.capitalize} ##{succeeded.first} #{verb_past}." if succeeded.size == 1

        "#{succeeded.size} #{noun}s #{verb_past}."
      end

      def failed_phrase(failed, _noun)
        return nil if failed.empty?

        "#{failed.size} failed: #{failed.map(&:first).join(", ")}."
      end
    end
  end
end
