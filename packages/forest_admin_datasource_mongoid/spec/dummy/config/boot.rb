# ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
#
# require "bundler/setup" # Set up gems listed in the Gemfile.
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Configure les gems listés dans Gemfile.

# Désactiver Bootsnap pour l'environnement 'test'
require 'bootsnap/setup' unless ENV['RAILS_ENV'] == 'test'