require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'
require 'Json'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  def self.build(options)
    uri = options[:uri]
    # TODO : auth
    # const authRq = superagent.post(`${uri}/forest/authentication`);
    # const authResp = await authRq.send({ authSecret });
    #
    # const { token } = authResp.body;
    token = ''

    ForestAdminRpcAgent::Facades::Container.logger.log('Info', "Getting schema from Rpc agent on #{uri}.")

    response = Utils::ApiRequester.new(uri, token).get('/forest_admin_rpc/rpc-schema')
    schema = JSON.parse(response.body, symbolize_names: true)

    ForestAdminDatasourceRpc::Datasource.new(options, schema)
  end
end
