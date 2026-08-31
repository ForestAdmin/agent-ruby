module ForestAdminDatasourceIntercom
  # Boot skeleton: it configures a client and registers no collection yet. The
  # collections follow in their own pull requests, each one bringing the
  # endpoints it reads.
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(access_token:, **options)
      super()
      @configuration = Configuration.new(access_token: access_token, **options)
      @client = Client.new(@configuration)

      register_collections
    end

    # The datasource is what a Rails error page or a `logger.debug` is likeliest
    # to print, and it holds the client whose connections carry the access token.
    # Every collection will reach that token the same way, through the
    # `@datasource` the toolkit's Collection keeps, so cutting the chain here
    # covers them too -- and spares the recursive dump the default `inspect`
    # walks into, a datasource and its collections pointing at each other.
    def inspect
      "#<#{self.class.name} collections=#{collections.keys.inspect}>"
    end

    private

    def register_collections; end
  end
end
