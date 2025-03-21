require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

SimpleCov.coverage_dir 'coverage'
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
end

# TODO
