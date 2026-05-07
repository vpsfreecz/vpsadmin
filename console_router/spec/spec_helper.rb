# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'base64'
require 'json'
require 'rack/test'
require 'rspec'

require_relative '../lib/vpsadmin/console_router'

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
