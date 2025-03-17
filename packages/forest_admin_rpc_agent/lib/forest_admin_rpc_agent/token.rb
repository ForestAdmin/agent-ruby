require 'openssl'
require 'json'

secret = 'MY_AUTH_SECRET'
body = ''

signature = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
puts signature
