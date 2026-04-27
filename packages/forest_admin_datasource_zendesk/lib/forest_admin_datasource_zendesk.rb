require_relative 'forest_admin_datasource_zendesk/version'
require 'logger'
require 'zeitwerk'
require 'forest_admin_datasource_toolkit'
require 'zendesk_api'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceZendesk
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class UnsupportedOperatorError < Error; end

  # Raised when a Zendesk API call fails for any reason other than the
  # well-known `RecordNotFound`. Wraps the underlying error so callers can
  # rescue a single class without depending on the zendesk_api gem.
  class APIError < Error; end

  class << self
    attr_writer :logger

    def logger
      @logger ||= default_logger
    end

    private

    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr).tap { |l| l.progname = 'forest_admin_datasource_zendesk' }
    end
  end
end
