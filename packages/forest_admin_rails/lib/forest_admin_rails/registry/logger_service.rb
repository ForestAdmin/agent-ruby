require 'mono_logger'

# TODO: move to a new agent package
module ForestAdminRails
  module Registry
    class LoggerService
      attr_reader :default_logger

      def initialize(logger_level = 'Info', logger = nil)
        @logger_level = logger_level
        @logger = logger
        @default_logger = MonoLogger.new('forest_admin')
        # TODO: HANDLE FORMATTER
      end

      def levels
        %w[Debug Info Warn Error]
      end
    end
  end
end
