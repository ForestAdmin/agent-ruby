require_relative 'forest_admin_datasource_mambu_payments/version'
require 'logger'
require 'zeitwerk'
require 'faraday'
require 'faraday/retry'
require 'forest_admin_datasource_toolkit'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceMambuPayments
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class UnsupportedOperatorError < Error; end

  # Raised when a Numeral API call fails. Carries the HTTP status and the
  # (parsed) response body so callers — smart actions in particular — can
  # surface the API's own validation message instead of a generic string.
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

      Logger.new($stderr).tap { |l| l.progname = 'forest_admin_datasource_mambu_payments' }
    end
  end
end
