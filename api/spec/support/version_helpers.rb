# frozen_string_literal: true

module VersionHelpers
  def api_versions
    header 'Accept', 'application/json'
    options '/'
    expect(last_response.status).to eq(200)

    root = json
    source = root.is_a?(Hash) && root['response'].is_a?(Hash) ? root['response'] : root

    versions_value = source.is_a?(Hash) ? (source['versions'] || source['version']) : nil

    versions =
      case versions_value
      when Hash
        versions_value.each_with_object([]) do |(ver, _desc), list|
          next if ver.to_s == 'default'

          list << ver.to_s
        end
      when Array
        versions_value.map do |v|
          v.is_a?(Hash) ? (v['version'] || v['id'] || v['name']) : v
        end.compact
      when String
        [versions_value]
      else
        []
      end

    expect(versions).not_to be_empty
    versions
  end

  def api_version
    api_versions.first
  end

  def vpath(path)
    ver = api_version.to_s
    ver = ver.sub(%r{\A/}, '')
    ver = ver.sub(/\Av/, '')
    ver = ver.split('/').first
    "/v#{ver}#{path}"
  end
end

RSpec.configure do |config|
  config.include VersionHelpers
end
