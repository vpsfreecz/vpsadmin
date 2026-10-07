# frozen_string_literal: true

require 'rack/test'
require_relative 'request_exception_diagnostics'

module ApiAppHelper
  include Rack::Test::Methods

  def app
    ApiAppHelper.app_instance
  end

  def self.app_instance
    @app_instance ||= RequestExceptionDiagnostics::App.new(VpsAdmin::API.default.app)
  end
end

RSpec.configure do |config|
  config.include ApiAppHelper
end
