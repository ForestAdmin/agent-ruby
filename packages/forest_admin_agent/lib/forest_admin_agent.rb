require_relative "forest_admin_agent/version"
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module ForestAdminAgent
  class Error < StandardError; end
  # Your code goes here...
end
