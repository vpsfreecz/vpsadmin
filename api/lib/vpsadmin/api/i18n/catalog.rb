# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module VpsAdmin
  module API
    module I18n
      class Catalog
        DEFAULT_LOCALE = 'en'
        LOCALE_DIR = 'api/lib/vpsadmin/api/locales'
        LOCALE_GLOB = "#{LOCALE_DIR}/*.yml".freeze

        KEY_PATTERNS = [
          /VpsAdmin::API::I18n\.(?:t|message)\(\s*['"]([a-z0-9_.]+)['"]/,
          /\bapi_(?:t|message)\(\s*['"]([a-z0-9_.]+)['"]/
        ].freeze

        SCAN_GLOBS = [
          'api/lib/vpsadmin/api.rb',
          'api/lib/vpsadmin/api/*.rb',
          'api/lib/vpsadmin/api/operations/**/*.rb',
          'api/lib/vpsadmin/api/resources/**/*.rb',
          'api/models/**/*.rb',
          'plugins/*/api/lib/**/*.rb',
          'plugins/*/api/models/**/*.rb',
          'plugins/*/api/resources/**/*.rb'
        ].freeze

        SCAN_EXCLUDES = [
          'api/lib/vpsadmin/api/i18n',
          'api/lib/vpsadmin/api/tasks',
          'api/models/transaction_chains',
          'plugins/*/api/models/transaction_chains'
        ].freeze

        def initialize(root:)
          @root = root
        end

        def update!
          expected = normalized_catalog(add_missing: true)

          locales.each do |locale|
            write_file(locale_file(locale), YAML.dump(locale => expected.fetch(locale)))
          end
        end

        def check!
          errors = []
          expected = normalized_catalog(add_missing: false)

          locales.each do |locale|
            path_name = locale_file(locale)
            path = absolute_path(path_name)

            unless File.exist?(path)
              errors << "#{path_name}: locale file is missing"
              next
            end

            content = YAML.dump(locale => expected.fetch(locale))
            errors << "#{path_name}: not normalized; run rake vpsadmin:i18n:update" \
              if File.read(path) != content
          end

          errors.concat(missing_key_errors)
          errors.concat(unused_key_errors)
          errors.concat(todo_errors)
          errors.concat(interpolation_errors)
          errors.concat(source_catalog_errors)

          return true if errors.empty?

          raise "vpsAdmin API i18n health check failed:\n#{errors.join("\n")}"
        end

        private

        attr_reader :root

        def normalized_catalog(add_missing:)
          current = locale_data
          keys = used_keys

          locales.to_h do |locale|
            data = current.fetch(locale, {})

            if add_missing
              keys.each do |key|
                set_nested(data, scoped_parts(key), 'TODO')
              end
            end

            [locale, deep_sort(data)]
          end
        end

        def missing_key_errors
          keys = used_keys
          locales.flat_map do |locale|
            values = flatten_values(locale_data.fetch(locale, {}))

            keys.reject { |key| values.has_key?("vpsadmin.#{key}") }.sort.map do |key|
              "#{locale}: missing vpsadmin.#{key}"
            end
          end
        end

        def unused_key_errors
          keys = used_keys

          locales.flat_map do |locale|
            flatten_values(locale_data.fetch(locale, {})).keys.filter_map do |key|
              next if keys.include?(key.delete_prefix('vpsadmin.'))
              next unless key.start_with?('vpsadmin.')

              "#{locale}: unused #{key}"
            end
          end
        end

        def todo_errors
          locales.flat_map do |locale|
            flatten_values(locale_data.fetch(locale, {})).filter_map do |key, value|
              next unless value.to_s.strip.empty? || value.to_s.match?(/\ATODO\b/i)

              "#{locale}: missing translation for #{key}"
            end
          end
        end

        def interpolation_errors
          reference = flatten_values(locale_data.fetch(DEFAULT_LOCALE, {}))

          locales.flat_map do |locale|
            next [] if locale == DEFAULT_LOCALE

            flatten_values(locale_data.fetch(locale, {})).filter_map do |key, value|
              next unless reference.has_key?(key)
              next if placeholders(reference.fetch(key)) == placeholders(value)

              "#{locale}: interpolation mismatch for #{key}"
            end
          end
        end

        def source_catalog_errors
          locales.flat_map do |locale|
            source = locale_data.dig(locale, 'vpsadmin', 'source')
            source ? ["#{locale}: legacy vpsadmin.source catalog is not allowed"] : []
          end
        end

        def used_keys
          @used_keys ||= source_files.each_with_object([]) do |file, ret|
            content = File.read(file)

            KEY_PATTERNS.each do |pattern|
              content.scan(pattern) do |match|
                key = match.first.delete_prefix('vpsadmin.')
                ret << key unless ret.include?(key)
              end
            end
          end
        end

        def locale_data
          @locale_data ||= locales.to_h do |locale|
            path = absolute_path(locale_file(locale))
            data = File.exist?(path) ? YAML.safe_load_file(path, aliases: true) || {} : {}

            [locale, data.fetch(locale, {})]
          end
        end

        def locales
          @locales ||= begin
            discovered = Dir[absolute_path(LOCALE_GLOB)].map do |path|
              File.basename(path, '.yml')
            end
            other_locales = discovered.reject { |locale| locale == DEFAULT_LOCALE }.sort
            [DEFAULT_LOCALE] + other_locales
          end
        end

        def locale_file(locale)
          File.join(LOCALE_DIR, "#{locale}.yml")
        end

        def source_files
          @source_files ||= SCAN_GLOBS.flat_map do |glob|
            Dir[absolute_path(glob)]
          end.reject do |file|
            rel = relative_path(file)
            SCAN_EXCLUDES.any? { |exclude| File.fnmatch?(exclude, rel) || rel.start_with?("#{exclude}/") }
          end.sort
        end

        def flatten_values(hash, prefix = nil)
          hash.each_with_object({}) do |(key, value), ret|
            name = [prefix, key].compact.join('.')

            if value.is_a?(Hash)
              ret.merge!(flatten_values(value, name))
            else
              ret[name] = value
            end
          end
        end

        def set_nested(hash, parts, value)
          last = parts.pop
          target = parts.reduce(hash) do |memo, key|
            memo[key] ||= {}
          end
          target[last] = value unless target.has_key?(last)
        end

        def scoped_parts(key)
          ['vpsadmin'] + key.split('.')
        end

        def placeholders(value)
          value.to_s.scan(/%\{([a-zA-Z0-9_]+)\}/).flatten.sort
        end

        def deep_sort(value)
          case value
          when Hash
            value.keys.sort.to_h { |key| [key, deep_sort(value[key])] }
          else
            value
          end
        end

        def write_file(path, content)
          abs = absolute_path(path)
          FileUtils.mkdir_p(File.dirname(abs))
          File.write(abs, content)
        end

        def absolute_path(path)
          File.join(root, path)
        end

        def relative_path(path)
          path.delete_prefix("#{root}/")
        end
      end
    end
  end
end
