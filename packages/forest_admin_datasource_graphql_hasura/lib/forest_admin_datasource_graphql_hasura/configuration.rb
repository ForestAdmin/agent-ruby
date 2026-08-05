module ForestAdminDatasourceGraphqlHasura
  class Configuration
    # polymorphic_relations declares associations explicitly when the metadata API
    # is unreachable: { 'comments' => { 'commentable' => %w[transfers cards] } }.
    # type_values overrides the Rails class name a table maps to, for those that
    # `classify` gets wrong: { 'bank_accounts' => 'Banking::Account' }.
    DEFAULTS = {
      headers: {},
      metadata_uri: nil,
      included_tables: nil,
      excluded_tables: [],
      polymorphic_relations: {},
      type_values: {},
      timeout: 30
    }.freeze

    attr_reader :uri, :headers, :metadata_uri, :included_tables, :excluded_tables,
                :polymorphic_relations, :type_values, :timeout

    def initialize(uri:, **options)
      raise ConfigurationError, 'uri is required' if uri.nil? || uri.empty?

      unknown = options.keys - DEFAULTS.keys
      raise ConfigurationError, "Unknown option(s): #{unknown.join(", ")}" if unknown.any?

      @uri = uri
      DEFAULTS.each { |option, default| instance_variable_set("@#{option}", options.fetch(option, default)) }
      # Only derivable from the conventional endpoint path: substituting on any
      # other uri would silently post metadata commands to the GraphQL endpoint.
      @metadata_uri ||= uri.include?('/v1/graphql') ? uri.sub('/v1/graphql', '/v1/metadata') : nil
    end

    def table_allowed?(table_name)
      return false if excluded_tables.include?(table_name)
      return included_tables.include?(table_name) unless included_tables.nil?

      true
    end
  end
end
