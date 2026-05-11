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
  class APIError < Error; end

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
