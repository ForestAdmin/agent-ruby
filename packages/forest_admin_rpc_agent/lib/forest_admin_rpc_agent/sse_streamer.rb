require 'json'

module ForestAdminRpcAgent
  class SseStreamer
    def initialize(io)
      @io = io
    end

    def write(object, event: nil)
      @io.write("event: #{event}\n") if event
      @io.write("data: #{JSON.dump(object)}\n\n")
      @io.flush
    end

    def close
      @io.close
    end
  end
end
