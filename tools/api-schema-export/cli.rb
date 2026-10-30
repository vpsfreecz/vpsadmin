#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'safety'

root = File.realpath('../..', __dir__)
options = { api_version: '7.0' }
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: tools/export-api-schema --output DIR [--api-version 7.0] | --prepare'
  opts.on('--output DIR') { |value| options[:output] = value }
  opts.on('--api-version VERSION') { |value| options[:api_version] = value }
  opts.on('--prepare', 'Install the isolated HaveAPI 0.32.0 tooling bundle only') { options[:prepare] = true }
end

begin
  parser.parse!
  raise OptionParser::InvalidArgument, 'unexpected arguments' unless ARGV.empty?
  raise OptionParser::MissingArgument, '--output' unless options[:prepare] || options[:output]
  raise OptionParser::InvalidArgument, 'only API 7.0 is supported' unless options[:api_version] == '7.0'

  VpsAdmin::SchemaExport::Safety.new(root:).check!
  ENV['RACK_ENV'] = 'test'
  ENV['VPSADMIN_PLUGINS'] = 'all'
  ENV['BUNDLE_GEMFILE'] = File.join(__dir__, 'Gemfile')
  ENV['BUNDLE_PATH'] = File.join(__dir__, '.gems')
  ENV['BUNDLE_IGNORE_CONFIG'] = '1'

  if options[:prepare]
    exec(Gem.ruby, Gem.bin_path('bundler', 'bundle'), 'install')
  end

  require 'bundler/setup'
  require_relative 'runner'
  VpsAdmin::SchemaExport::Runner.new(root:, **options).run
rescue OptionParser::ParseError, VpsAdmin::SchemaExport::UnsafeInput => e
  warn e.message
  exit 1
end
