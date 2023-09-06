require_relative "forestadmin_agent/version"
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module ForestadminAgent
  class Error < StandardError; end
  # Your code goes here...
end
