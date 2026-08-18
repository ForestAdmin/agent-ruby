require_relative 'forest_admin_datasource_pylon/version'
require 'json'
require 'logger'
require 'zeitwerk'
require 'faraday'
require 'faraday/retry'
require 'forest_admin_datasource_toolkit'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourcePylon
  class Error < StandardError; end
  class ConfigurationError < Error; end

  # A filter Pylon cannot express. It descends from the toolkit's ValidationError
  # rather than from the package's own Error so the agent answers 400 carrying
  # the message instead of a 500 "Unexpected error": every one of these names a
  # condition the operator set and can change, and the message is the only place
  # they learn which one.
  class UnsupportedOperatorError < ForestAdminDatasourceToolkit::Exceptions::ValidationError; end

  # Raised when a Pylon API call fails. Carries the HTTP status and the
  # (parsed) response body so callers — smart actions in particular — can
  # surface Pylon's own validation message instead of a generic string.
  class APIError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  class << self
    attr_writer :logger

    def logger
      @logger ||= default_logger
    end

    private

    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr).tap { |l| l.progname = 'forest_admin_datasource_pylon' }
    end
  end
end
