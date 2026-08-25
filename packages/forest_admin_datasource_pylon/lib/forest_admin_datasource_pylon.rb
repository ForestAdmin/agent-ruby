require_relative 'forest_admin_datasource_pylon/version'
require 'json'
require 'logger'
require 'uri'
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

  # The three write errors below descend from ValidationError for that same
  # reason: each names something the operator did and can undo.

  # A verb Pylon's API has no endpoint for, a field it only accepts in the other
  # direction, or a write reaching more records than one pass may cover.
  class UnsupportedWriteError < ForestAdminDatasourceToolkit::Exceptions::ValidationError; end

  # A write Pylon performed on some of its records and then failed on: one
  # record is one request, so the ones before the failure stay written, and a
  # retry of the whole selection would write them a second time.
  class PartialWriteError < ForestAdminDatasourceToolkit::Exceptions::ValidationError; end

  # A write Pylon itself refused, carrying the reason it gave — the likeliest
  # way a write fails. Only its 4xx travels this way: a 5xx or a dropped
  # connection is not the operator's to act on and stays the APIError it was.
  class WriteRejectedError < ForestAdminDatasourceToolkit::Exceptions::ValidationError; end

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
