require_relative 'forest_admin_agent/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('oauth2' => 'OAuth2')
loader.setup

module ForestAdminAgent
  class Error < StandardError; end
  # Your code goes here...
end
