require_relative 'forest_admin_datasource_graphql_hasura/version'
require 'logger'
require 'set'
require 'zeitwerk'
require 'forest_admin_datasource_toolkit'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/forest_admin_datasource_graphql_hasura/introspection/structures.rb")
loader.setup

require_relative 'forest_admin_datasource_graphql_hasura/introspection/structures'

module ForestAdminDatasourceGraphqlHasura
  class Error < StandardError; end
  class ConfigurationError < Error; end

  # Inherits from the toolkit exception so the agent's error translator surfaces
  # the actual message with a 400 instead of an opaque 500 "Unexpected error".
  # Reserved for errors Hasura itself returns; transport failures are not the
  # user's doing and raise TransportError instead.
  class GraphqlError < ForestAdminDatasourceToolkit::Exceptions::ValidationError; end

  # An unreachable endpoint is an infrastructure incident, not a client mistake:
  # 503 keeps HTTP monitoring truthful, while inheriting the toolkit exception
  # still lets the error translator surface the actionable message.
  class TransportError < ForestAdminDatasourceToolkit::Exceptions::ForestException
    def status
      503
    end
  end

  class IntrospectionError < Error; end

  class << self
    attr_writer :logger

    def logger
      @logger ||= default_logger
    end

    private

    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr).tap { |l| l.progname = 'forest_admin_datasource_graphql_hasura' }
    end
  end
end
