require 'json'

module ForestAdminRpcAgent
  class SseStreamer
    def initialize(yielder)
      @yielder = yielder
    end

    def write(object, event: nil)
      @yielder << "event: #{event}\n" if event
      @yielder << "data: #{JSON.dump(object)}\n\n"
    end
  end
end
