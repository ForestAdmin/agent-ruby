module ForestAdminDatasourceIntercom
  # Boot skeleton: it registers no collection yet. Configuration and the Faraday
  # client come next, then the collections, each behind its own pull request --
  # so this one is what proves the package is wired into the monorepo (rubocop,
  # rspec, coverage, release) before any behaviour depends on it.
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    def initialize
      super
      register_collections
    end

    # The datasource is what a Rails error page or a `logger.debug` is likeliest
    # to print, and it will soon hold the client carrying the access token.
    # Cutting the default dump here also spares the recursive walk of a
    # datasource and its collections pointing at each other.
    def inspect
      "#<#{self.class.name} collections=#{collections.keys.inspect}>"
    end

    private

    def register_collections; end
  end
end
