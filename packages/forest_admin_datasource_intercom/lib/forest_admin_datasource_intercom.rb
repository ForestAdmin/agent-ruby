require_relative 'forest_admin_datasource_intercom/version'
require 'cgi/escape'
require 'json'
require 'logger'
require 'set'
require 'time'
require 'uri'
require 'yaml'
require 'zeitwerk'
require 'faraday'
require 'faraday/retry'
require 'forest_admin_datasource_toolkit'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceIntercom
  class Error < StandardError; end
  class ConfigurationError < Error; end

  # A filter Intercom cannot express exactly: an operator its search DSL refuses
  # on that field, a tree deeper than the two levels it allows, or a group past
  # its fifteen filters. It descends from the toolkit's ValidationError rather
  # than from this package's Error so the agent answers 400 carrying the message
  # instead of a 500 "Unexpected error" -- each one names something the operator
  # set and can change, and the message is the only place they learn which.
  #
  # This datasource refuses rather than approximates: a result that looks
  # filtered and is not is worse than an explicit refusal.
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
