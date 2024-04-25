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

        def self.detect_mime_type(base_64_value)
          signatures = {
            'JVBERi0' => 'application/pdf',
            'R0lGODdh' => 'image/gif',
            'R0lGODlh' => 'image/gif',
            'iVBORw0KGgo' => 'image/png',
            'TU0AK' => 'image/tiff',
            '/9j/' => 'image/jpg',
            'UEs' => 'application/vnd.openxmlformats-officedocument.',
            'PK' => 'application/zip'
          }

          signatures.each do |key, value|
            return value if base_64_value.index(key)&.zero?
          end

          'application/octet-stream'
        end
      end
    end
  end
end
