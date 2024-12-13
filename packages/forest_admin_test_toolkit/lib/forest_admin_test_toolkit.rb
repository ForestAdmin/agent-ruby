require_relative 'forest_admin_test_toolkit/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminTestToolkit
  class Error < StandardError; end
  # Your code goes here...
end
