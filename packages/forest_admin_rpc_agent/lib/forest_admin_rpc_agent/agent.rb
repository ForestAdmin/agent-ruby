module ForestAdminRpcAgent
  class Agent < ForestAdminAgent::Builder::AgentFactory
    attr_reader :rpc_collections

    def setup(options)
      super
      @rpc_collections = []
    end

    def send_schema(_force: nil)
      ForestAdminAgent::Facades::Container.logger.log('Info', 'Started as RPC agent, schema not sent.')
    end

    def mark_collections_as_rpc(*names)
      @rpc_collections.push(*names)
      self
    end

    def start
      puts '🚀 Starting ForestAdmin RPC Agent...'
    end

    def stop
      puts '🛑 Stopping ForestAdmin RPC Agent...'
    end
  end
end
