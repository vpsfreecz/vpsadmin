# frozen_string_literal: true

require 'json'

module JsonHelpers
  def json
    JSON.parse(last_response.body)
  end
end

RSpec.configure do |config|
  config.include JsonHelpers
end
