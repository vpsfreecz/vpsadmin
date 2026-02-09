# frozen_string_literal: true

require 'json'

module EndpointInventory
  module_function

  def versions(app_helper)
    request_root(app_helper)
    response = parse_response(app_helper.last_response.body)

    versions_value =
      if response.is_a?(Hash)
        response['versions'] || response['version']
      end

    versions = normalize_versions(versions_value)
    raise 'No API versions found in root response' if versions.empty?

    versions
  end

  def scopes_for_version(app_helper, ver)
    path = version_path(ver)
    request_version(app_helper, path)
    response = parse_response(app_helper.last_response.body)

    resources = response.is_a?(Hash) ? (response['resources'] || {}) : {}
    scopes = []
    walk_resources(resources, scopes, prefix: nil)
    scopes.sort.uniq
  end

  def all_scopes(app_helper, only_first_version: true)
    vers = versions(app_helper)
    vers = vers.first(1) if only_first_version

    vers.flat_map { |v| scopes_for_version(app_helper, v) }.sort.uniq
  end

  def walk_resources(resources_hash, scopes, prefix:)
    return unless resources_hash.is_a?(Hash)

    resources_hash.each do |name, res|
      path = prefix ? "#{prefix}.#{name}" : name.to_s

      actions = res.is_a?(Hash) ? res['actions'] : nil
      if actions.is_a?(Hash)
        actions.each_key do |action_name|
          scopes << "#{path}##{action_name}"
        end
      end

      sub = res.is_a?(Hash) ? res['resources'] : nil
      walk_resources(sub, scopes, prefix: path)
    end
  end

  def request_root(app_helper)
    app_helper.header 'Accept', 'application/json'
    if app_helper.respond_to?(:options)
      app_helper.options '/'
    else
      app_helper.get '/'
    end

    status = app_helper.last_response.status
    return if status == 200

    raise "OPTIONS / failed: #{status} body=#{app_helper.last_response.body}"
  end

  def request_version(app_helper, path)
    app_helper.header 'Accept', 'application/json'
    if app_helper.respond_to?(:options)
      app_helper.options path
    else
      app_helper.get path
    end

    status = app_helper.last_response.status
    return if status == 200

    raise "OPTIONS #{path} failed: #{status} body=#{app_helper.last_response.body}"
  end

  def parse_response(body)
    root = JSON.parse(body)
    if root.is_a?(Hash) && root['response'].is_a?(Hash)
      root['response']
    else
      root
    end
  end

  def normalize_versions(value)
    case value
    when Hash
      value.each_with_object([]) do |(ver, _desc), list|
        next if ver.to_s == 'default'

        list << ver.to_s
      end
    when Array
      value.map do |v|
        v.is_a?(Hash) ? (v['version'] || v['id'] || v['name']) : v
      end.compact.map(&:to_s)
    when String
      [value]
    else
      []
    end
  end

  def version_path(ver)
    ver_str = ver.to_s
    if ver_str.include?('/')
      ver_str.start_with?('/') ? ver_str : "/#{ver_str}"
    else
      version_prefix = ver_str.start_with?('v') ? ver_str : "v#{ver_str}"
      "/#{version_prefix}/"
    end
  end
end
