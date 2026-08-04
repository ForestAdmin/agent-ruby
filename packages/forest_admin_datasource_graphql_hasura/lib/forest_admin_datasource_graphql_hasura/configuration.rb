module ForestAdminDatasourceGraphqlHasura
  class Configuration
    DEFAULT_TIMEOUT = 30

    attr_reader :uri, :headers, :metadata_uri, :included_tables, :excluded_tables,
                :polymorphic_relations, :type_values, :timeout

    # polymorphic_relations declares associations explicitly when the metadata API
    # is unreachable: { 'comments' => { 'commentable' => %w[transfers cards] } }.
    # type_values overrides the Rails class name a table maps to, for those that
    # `classify` gets wrong: { 'bank_accounts' => 'Banking::Account' }.
    def initialize(uri:, headers: {}, metadata_uri: nil, included_tables: nil, excluded_tables: [],
                   polymorphic_relations: {}, type_values: {}, timeout: DEFAULT_TIMEOUT)
      raise ConfigurationError, 'uri is required' if uri.nil? || uri.empty?

      @uri = uri
      @headers = headers
      @metadata_uri = metadata_uri || uri.sub('/v1/graphql', '/v1/metadata')
      @included_tables = included_tables
      @excluded_tables = excluded_tables
      @polymorphic_relations = polymorphic_relations
      @type_values = type_values
      @timeout = timeout
    end

    def table_allowed?(table_name)
      return false if excluded_tables.include?(table_name)
      return included_tables.include?(table_name) unless included_tables.nil?

      true
    end
  end
end
