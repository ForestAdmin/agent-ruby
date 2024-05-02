require 'base64'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Binary
      class BinaryHelper
        def self.bin_to_hex(data)
          data.unpack1('H*')
        end

        def self.hex_to_bin(data)
          data.scan(/../).map(&:hex).pack('c*')
        end
      end
    end
  end
end
