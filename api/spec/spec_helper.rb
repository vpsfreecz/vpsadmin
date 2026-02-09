# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'bundler/setup'
require 'rspec'

# Load support helpers (will be populated in later sessions)
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
end
