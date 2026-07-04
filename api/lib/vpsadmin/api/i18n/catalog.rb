# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

module VpsAdmin
  module API
    module I18n
      class Catalog
        DEFAULT_LOCALE = 'en'
        LOCALE_DIR = 'api/lib/vpsadmin/api/locales'
        LOCALE_GLOB = "#{LOCALE_DIR}/*.yml".freeze
        PARAMETER_CATALOG_REQUIRED = true
        RESERVED_RESOURCE_KEYS = %w[actions attributes input meta output].freeze
        GENERATED_HEADER = <<~HEADER
          # This file is maintained by rake vpsadmin:i18n:update.
          # The key structure is generated from API source and HaveAPI parameter metadata.
          # Edit translations here, then rerun rake vpsadmin:i18n:update.
        HEADER

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
            write_file(locale_file(locale), render_locale(locale, expected.fetch(locale)))
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

            content = render_locale(locale, expected.fetch(locale))
            errors << "#{path_name}: not normalized; run rake vpsadmin:i18n:update" \
              if File.read(path) != content
          end

          errors.concat(missing_key_errors)
          errors.concat(unused_key_errors)
          errors.concat(todo_errors)
          errors.concat(interpolation_errors)
          errors.concat(source_catalog_errors)
          errors.concat(resource_key_collision_errors)

          return true if errors.empty?

          raise "vpsAdmin API i18n health check failed:\n#{errors.join("\n")}"
        end

        private

        attr_reader :root

        def normalized_catalog(add_missing:)
          current = deep_dup(locale_data)
          keys = used_keys
          parameter_defaults = parameter_catalog_required? ? parameter_metadata : {}
          parameter_keys = parameter_defaults.keys

          locales.to_h do |locale|
            original_data = current.fetch(locale, {})
            original_values = flatten_values(original_data)
            data = prune_vpsadmin_catalog(original_data, keys)

            keys.each do |key|
              if locale == DEFAULT_LOCALE && parameter_defaults.has_key?(key)
                set_nested(data, scoped_parts(key), parameter_defaults.fetch(key), overwrite: true)

              elsif add_missing
                value = if parameter_keys.include?(key)
                          migrated_parameter_translation(original_values, key) || 'TODO'
                        else
                          'TODO'
                        end

                set_nested(data, scoped_parts(key), value)
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
          @used_keys ||= (source_keys + (parameter_catalog_required? ? parameter_metadata.keys : [])).uniq
        end

        def parameter_catalog_required?
          PARAMETER_CATALOG_REQUIRED
        end

        def source_keys
          @source_keys ||= source_files.each_with_object([]) do |file, ret|
            content = File.read(file)

            KEY_PATTERNS.each do |pattern|
              content.scan(pattern) do |match|
                key = match.first.delete_prefix('vpsadmin.')
                ret << key unless ret.include?(key)
              end
            end
          end
        end

        def parameter_metadata
          @parameter_metadata ||= compact_parameter_metadata(parameter_metadata_items)
        end

        def compact_parameter_metadata(items)
          @parameter_metadata_sources = {}
          ret = {}
          entries = normalized_parameter_metadata_items(items).each_with_index.to_a
          max_candidates = entries.map { |item, _| item.fetch(:keys).length }.max || 0

          (max_candidates - 1).downto(0) do |index|
            entries = promote_unambiguous_parameter_keys(entries, index, ret)
          end

          ret
        end

        def promote_unambiguous_parameter_keys(entries, index, ret)
          covered = []

          entries.group_by { |item, _| item.fetch(:keys)[index] }.each do |key, group|
            next unless key

            values = group.map { |item, _| item.fetch(:value) }.uniq
            next unless values.length == 1

            ret[key] = values.first
            @parameter_metadata_sources[key] = group.map { |item, _| item.fetch(:source) }
            covered.concat(group.map(&:last))
          end

          entries.reject { |_, index| covered.include?(index) }
        end

        def normalized_parameter_metadata_items(items)
          items.map do |item|
            {
              keys: item.fetch(:keys).map { |key| parameter_metadata_key(key) },
              value: item.fetch(:value),
              source: item
            }
          end
        end

        def parameter_metadata_key(key)
          key = key.to_s
          prefix = "#{VpsAdmin::API::I18n::PARAMETER_SCOPE}."

          unless key.start_with?(prefix)
            raise "parameter metadata key #{key.inspect} is outside #{VpsAdmin::API::I18n::PARAMETER_SCOPE.inspect}"
          end

          key.delete_prefix(prefix)
        end

        def parameter_metadata_items
          @parameter_metadata_items ||= with_api_runtime do |api|
            unless api.respond_to?(:parameter_metadata_i18n_items)
              raise 'HaveAPI with parameter metadata i18n catalog support is required'
            end

            original_scope = api.parameter_i18n_scope if api.respond_to?(:parameter_i18n_scope)
            previous_locale = ::I18n.locale
            api.parameter_i18n_scope = VpsAdmin::API::I18n::PARAMETER_SCOPE if api.respond_to?(:parameter_i18n_scope=)

            begin
              ::I18n.with_locale(DEFAULT_LOCALE) do
                api.parameter_metadata_i18n_items
              end
            ensure
              ::I18n.locale = previous_locale
              api.parameter_i18n_scope = original_scope if api.respond_to?(:parameter_i18n_scope=)
            end
          end
        end

        def migrated_parameter_translation(flat_values, key)
          sources = @parameter_metadata_sources.fetch(key, [])
          values = sources.filter_map do |item|
            legacy_parameter_metadata_keys(item).filter_map do |legacy_key|
              value = flat_values["vpsadmin.#{legacy_key}"]
              next if value.to_s.strip.empty? || value.to_s.match?(/\ATODO\b/i)

              value
            end.first
          end.uniq

          values.first if values.length == 1
        end

        def legacy_parameter_metadata_keys(item)
          resource_path = item.fetch(:resource_path)
          exact = [
            'parameters',
            'resources',
            *resource_path,
            'actions',
            item.fetch(:action)
          ]
          exact += ['meta', item[:meta_type]] if item[:meta_type]
          exact += [
            item.fetch(:direction),
            'parameters',
            item.fetch(:param),
            item.fetch(:kind)
          ]

          resource = [
            'parameters',
            'resources',
            *resource_path
          ]
          resource += ['meta', item[:meta_type]] if item[:meta_type]
          resource += [
            'parameters',
            item.fetch(:param),
            item.fetch(:kind)
          ]

          attribute = [
            'parameters',
            'attributes',
            item.fetch(:param),
            item.fetch(:kind)
          ]

          [exact, resource, attribute].map { |parts| parts.compact.join('.') }
        end

        def resource_key_collision_errors
          return [] unless parameter_catalog_required?

          paths = parameter_metadata_items.filter_map { |item| item[:resource_path] }.uniq
          paths.filter_map do |path|
            collision = path.each_with_index.detect do |segment, index|
              index > 0 && RESERVED_RESOURCE_KEYS.include?(segment.to_s)
            end

            next unless collision

            segment, = collision
            "resource path #{path.join('.')} collides with reserved i18n key #{segment.inspect}"
          end
        end

        def with_api_runtime
          original_env = ENV.fetch('RACK_ENV', nil)
          ENV['RACK_ENV'] = 'test'

          require 'rspec'
          require absolute_path('api/spec/support/db_setup')

          SpecDbSetup.establish_connection!
          SpecDbSetup.ensure_database_exists!

          silence_stdout do
            ActiveRecord::Schema.verbose = false if defined?(ActiveRecord::Schema)
            ActiveRecord::Migration.verbose = false if defined?(ActiveRecord::Migration)
            SpecDbSetup.load_schema!
          end

          require absolute_path('api/lib/vpsadmin')
          require absolute_path('api/spec/support/spec_plugins')
          require absolute_path('api/spec/support/spec_seed')

          SpecSeed.seed_language_if_needed!
          SpecDbSetup.seed_minimal_sysconfig!
          SpecDbSetup.seed_minimal_cluster_resources!

          api = VpsAdmin::API.default

          silence_stdout do
            SpecPlugins.migrate_enabled_plugins!
          end

          SpecSeed.bootstrap!

          yield api
        ensure
          if original_env
            ENV['RACK_ENV'] = original_env
          else
            ENV.delete('RACK_ENV')
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

        def render_locale(locale, data)
          GENERATED_HEADER + YAML.dump(locale => data)
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

        def prune_vpsadmin_catalog(data, keys)
          ret = deep_dup(data)
          vpsadmin = ret['vpsadmin']
          return ret unless vpsadmin.is_a?(Hash)

          key_lookup = keys.to_h { |key| [key, true] }
          pruned = prune_i18n_tree(vpsadmin, key_lookup)

          if pruned
            ret['vpsadmin'] = pruned
          else
            ret.delete('vpsadmin')
          end

          ret
        end

        def prune_i18n_tree(value, keys, prefix = nil)
          if value.is_a?(Hash)
            children = value.each_with_object({}) do |(key, child), ret|
              name = [prefix, key].compact.join('.')
              pruned = prune_i18n_tree(child, keys, name)
              ret[key] = pruned unless pruned.nil?
            end

            return children unless children.empty?

            keys[prefix] ? value : nil
          elsif keys[prefix]
            value
          end
        end

        def set_nested(hash, parts, value, overwrite: false)
          parts = parts.dup
          last = parts.pop
          target = parts.reduce(hash) do |memo, key|
            memo[key] ||= {}
          end
          target[last] = value if overwrite || !target.has_key?(last)
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

        def deep_dup(value)
          case value
          when Hash
            value.to_h { |key, child| [key, deep_dup(child)] }
          when Array
            value.map { |child| deep_dup(child) }
          else
            value
          end
        end

        def silence_stdout
          original_stdout = $stdout

          File.open(File::NULL, 'w') do |null|
            $stdout = null
            yield
          end
        ensure
          $stdout = original_stdout
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
