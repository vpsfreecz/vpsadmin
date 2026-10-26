# frozen_string_literal: true

require 'json'
require 'digest'
require 'uri'

module VpsAdmin
  module SchemaExport
    module Snapshot
      PROSE = %w[description label examples message comment title].freeze

      module_function

      def canonical(value)
        "#{JSON.pretty_generate(sort(value))}\n"
      end

      def sort(value)
        case value
        when Hash
          value.keys.sort.to_h { |key| [key, sort(value.fetch(key))] }
        when Array
          value.map { |item| sort(item) }
        else
          value
        end
      end

      # Maps, choice keys and Custom/default data have their own context. A real
      # parameter called 'description' must survive removal of descriptive prose.
      def sanitize(value, context = :description)
        return value.map { |item| sanitize(item, context) } if value.is_a?(Array)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, item), result|
          next if PROSE.include?(key) && !%i[map data choices].include?(context)
          next if context == :description && key == 'default' && value['protected'] == true

          validate_endpoint!(key, item) if context == :description && !item.nil?
          result[key] = if context == :validators && key == 'custom'
                          true
                        elsif context == :choices
                          nil
                        else
                          sanitize(item, child_context(context, key, item))
                        end
        end
      end

      def validate_endpoint!(key, value)
        if key.end_with?('_url')
          uri = URI.parse(value)
          unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
            raise UnsafeInput, 'Unsafe machine URL in mounted description'
          end

          path = uri.path
        elsif %w[path help].include?(key) || key.end_with?('_path')
          path, query = value.is_a?(String) ? value.split('?', 2) : [nil, nil]
          unless query.nil? || (key == 'help' && query.match?(/\Amethod=(GET|POST|PUT|PATCH|DELETE|OPTIONS)\z/))
            raise UnsafeInput, 'Unsafe machine path query in mounted description'
          end
        else
          return
        end

        unless path.is_a?(String) && path.start_with?('/') && !path.start_with?('//') && !path.match?(/[\\#]/) &&
               path.split('/').none? do |segment|
                 decoded = URI::DEFAULT_PARSER.unescape(segment)
                 %w[. ..].include?(decoded) || decoded.match?(%r{[/\\\x00-\x1f\x7f]})
               end
          raise UnsafeInput, 'Unsafe machine path in mounted description'
        end
      rescue URI::InvalidURIError, TypeError
        raise UnsafeInput, 'Invalid machine endpoint in mounted description'
      end

      def child_context(context, key, item)
        return :data if %i[data choices].include?(context)
        return :description if context == :map
        return :map if %w[resources actions parameters authentication].include?(key)
        return :data if %w[default format].include?(key) && context != :validator
        return item.is_a?(Hash) ? :choices : :data if key == 'values'
        return :validators if key == 'validators'
        return :validator if context == :validators

        :description
      end

      def build(description:, api_version:, protocol_version:)
        raise UnsafeInput, 'Unsupported exported protocol' unless protocol_version.match?(/\A2\.\d+\z/)

        description = JSON.parse(JSON.generate(description))
        unless description['help'] == "/v#{api_version}/" &&
               %w[resources authentication meta].all? { |key| description[key].is_a?(Hash) }
          raise UnsafeInput, 'Mounted description does not match the requested API version'
        end

        {
          'schema_format' => 1,
          'api_version' => api_version,
          'protocol_version' => protocol_version,
          'source_url' => "https://schema.invalid/v#{api_version}/",
          'profile' => 'vpsadmin-full-fixture',
          'mount_path' => '/',
          'description' => sanitize(description)
        }
      end

      def inventory(description)
        scopes = []
        resource_count = walk_resources(description.fetch('resources'), [], scopes)
        {
          'resources' => resource_count,
          'actions' => scopes.length,
          'parameters' => parameter_count(description),
          'scopes_sha256' => Digest::SHA256.hexdigest("#{scopes.sort.join("\n")}\n")
        }
      end

      def walk_resources(resources, parents, scopes)
        resources.sum do |name, resource|
          path = parents + [name]
          resource.fetch('actions').each do |action_name, action|
            scope = "#{path.join('.')}##{action_name}"
            unless action['scope'] == scope && action['path'].is_a?(String) &&
                   action['path'].start_with?('/v7.0/') && action['method'].is_a?(String)
              raise UnsafeInput, "Invalid mounted operation: #{scope}"
            end

            scopes << scope
          end
          1 + walk_resources(resource.fetch('resources'), path, scopes)
        end
      end

      def parameter_count(value, context = :description)
        return 0 if %i[data choices].include?(context)

        case value
        when Hash
          value.sum do |key, item|
            count = key == 'parameters' && context == :description && item.is_a?(Hash) ? item.length : 0
            count + parameter_count(item, child_context(context, key, item))
          end
        when Array
          value.sum { |item| parameter_count(item, context) }
        else
          0
        end
      end
    end
  end
end
