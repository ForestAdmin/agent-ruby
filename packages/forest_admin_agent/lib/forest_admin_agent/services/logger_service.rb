require 'mono_logger'

module ForestAdminAgent
  module Services
    class LoggerService
      attr_reader :default_logger

      LEVELS = {
        'Info' => Logger::INFO,
        'Debug' => Logger::DEBUG,
        'Warn' => Logger::WARN,
        'Error' => Logger::ERROR
      }.freeze

      def initialize(logger_level = 'Info', logger = nil)
        @logger_level = logger_level
        @logger = logger
        @default_logger = MonoLogger.new($stdout)
      end

      def log(level, message)
        if @logger
          eval(@logger).call(get_level(level), message)
        else
          @default_logger.add(get_level(level), message)
        end
        @logger || @default_logger
      end

      def get_level(level)
        LEVELS[level]
      end
    end
  end
end
