# frozen_string_literal: true

require 'json'

RSpec.describe ApiAppHelper do
  it 'exposes at least one version and each version responds' do
    header 'Accept', 'application/json'
    options '/'
    expect(last_response.status).to eq(200)

    root = JSON.parse(last_response.body)
    response = root['response']
    expect(response).to be_a(Hash)

    versions =
      if response['versions'].is_a?(Hash)
        response['versions'].each_with_object([]) do |(ver, desc), list|
          next if ver.to_s == 'default'

          value = if desc.is_a?(Hash) && desc['help'].is_a?(String)
                    desc['help']
                  else
                    ver
                  end
          list << value
        end
      else
        []
      end

    expect(versions).not_to be_empty

    versions.each do |ver|
      header 'Accept', 'application/json'
      ver_str = ver.to_s
      if ver_str.include?('/')
        path = ver_str.start_with?('/') ? ver_str : "/#{ver_str}"
      else
        version_prefix = ver_str.start_with?('v') ? ver_str : "v#{ver_str}"
        path = "/#{version_prefix}/"
      end
      options path
      message = "Expected #{path} to respond, got #{last_response.status} body=#{last_response.body}"
      expect(last_response.status).to eq(200), message
    end
  end
end
