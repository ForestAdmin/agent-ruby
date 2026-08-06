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
      # An explicit nil means "the default" (`headers: nil` must not crash every
      # request), and `default.dup` keeps the DEFAULTS hashes and arrays from
      # being shared — and mutated — across Configuration instances.
      DEFAULTS.each do |option, default|
        instance_variable_set("@#{option}", options[option].nil? ? default.dup : options[option])
      end
      validate_polymorphic_relations
      validate_table_lists
      # Only derivable from the conventional endpoint path: substituting on any
      # other uri would silently post metadata commands to the GraphQL endpoint.
      @metadata_uri ||= uri.include?('/v1/graphql') ? uri.sub('/v1/graphql', '/v1/metadata') : nil
    end

    # Accepts every spelling a table goes by (root field and type name): an
    # exclusion must hold under renaming, or it would silently re-expose data.
    def table_allowed?(*table_names)
      return false if table_names.any? { |name| excluded_tables.include?(name) }
      return (table_names & included_tables).any? unless included_tables.nil?

      true
    end

    private

    # A String by mistake (`included_tables: "users"`) would silently become a
    # substring check instead of a name match.
    def validate_table_lists
      return if excluded_tables.is_a?(Array) && (included_tables.nil? || included_tables.is_a?(Array))

      raise ConfigurationError, 'included_tables and excluded_tables must be arrays of table names'
    end

    # A misshapen declaration would otherwise crash deep inside introspection as
    # an opaque NoMethodError instead of naming the option.
    def validate_polymorphic_relations
      valid = polymorphic_relations.is_a?(Hash) && polymorphic_relations.all? do |_, bases|
        bases.is_a?(Hash) && bases.all? { |_, targets| targets.is_a?(Array) }
      end

      return if valid

      raise ConfigurationError,
            "polymorphic_relations must be { 'table' => { 'association' => ['target', ...] } }"
    end
  end
end
