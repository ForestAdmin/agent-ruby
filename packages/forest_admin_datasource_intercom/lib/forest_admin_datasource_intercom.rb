require_relative 'forest_admin_datasource_intercom/version'
require 'cgi/escape'
require 'json'
require 'logger'
require 'set'
require 'time'
require 'uri'
require 'yaml'
require 'zeitwerk'
# Required explicitly rather than relied on via the toolkit: `active_support` brings the autoload
# `Time.use_zone` needs, `active_support/time` brings `Time.zone` (see `Query::CallerZone`).
require 'active_support'
require 'active_support/time'
require 'faraday'
require 'faraday/retry'
require 'forest_admin_datasource_toolkit'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceIntercom
  class Error < StandardError; end
  class ConfigurationError < Error; end

  # Descends from the toolkit's ValidationError so the agent answers 400 with the message, not a 500:
  # the datasource refuses a filter Intercom cannot express exactly rather than approximating it.
  class UnsupportedOperatorError < ForestAdminDatasourceToolkit::Exceptions::ValidationError; end

  # Raised when an Intercom API call fails. Carries the HTTP status and the
  # parsed response body so callers -- smart actions in particular -- can
  # surface Intercom's own error message instead of a generic string.
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

      Logger.new($stderr).tap { |l| l.progname = 'forest_admin_datasource_intercom' }
    end
  end
end
