# frozen_string_literal: true

require 'rack/test'
require 'json'

module ApiAppHelper
  API_ROOT = File.expand_path('../..', __dir__).freeze
  DIAGNOSTIC_SOURCE_PREFIXES = %w[lib models spec].map { |dir| "#{API_ROOT}/#{dir}/" }.freeze

  include Rack::Test::Methods

  def app
    ApiAppHelper.app_instance
  end

  class << self
    def app_instance
      @app_instance ||= begin
        app = VpsAdmin::API.default.app
        app.settings.api_server.connect_hook(:request_exception) do |ret, _context, exception|
          report_request_exception(exception)
          ret
        end
        app
      end
    end

    private

    def report_request_exception(exception)
      record = { causes: diagnostic_causes(exception) }
      record[:example_id] = RSpec.current_example.id if RSpec.current_example
      warn "API_SPEC_REQUEST_EXCEPTION #{JSON.generate(record)}"
    rescue StandardError
      begin
        warn 'API_SPEC_REQUEST_EXCEPTION {"diagnostic_failed":true}'
      rescue StandardError
        nil
      end
    end

    def diagnostic_causes(exception)
      causes = []
      while exception && causes.length < 4
        entry = { class: exception.class.name }.compact
        location = exception.backtrace_locations&.find do |frame|
          path = frame.absolute_path
          path && DIAGNOSTIC_SOURCE_PREFIXES.any? { |prefix| path.start_with?(prefix) }
        end
        if location
          entry[:file] = "api/#{location.absolute_path.delete_prefix("#{API_ROOT}/")}"
          entry[:line] = location.lineno
        end
        if exception.is_a?(Mysql2::Error)
          errno = exception.error_number
          state = exception.sql_state
          entry[:errno] = errno if errno.is_a?(Integer)
          entry[:sqlstate] = state if state.is_a?(String) && /\A[A-Z0-9]{5}\z/.match?(state)
        end
        causes << entry
        exception = exception.cause
      end
      causes
    end
  end
end

RSpec.configure do |config|
  config.include ApiAppHelper
end
