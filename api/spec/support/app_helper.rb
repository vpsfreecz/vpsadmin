# frozen_string_literal: true

require 'rack/test'

module ApiAppHelper
  include Rack::Test::Methods

  def app
    VpsAdmin::API.default.app
  end
end

RSpec.configure do |config|
  config.include ApiAppHelper
end
