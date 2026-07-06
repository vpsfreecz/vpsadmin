# frozen_string_literal: true

module VpsAdmin
  module API
    module I18n
      DEFAULT_LOCALE = :en
      LOCALE_HEADER = 'Accept-Language'
      PARAMETER_SCOPE = 'vpsadmin'

      class << self
        def setup
          ::I18n.load_path |= locale_paths
        end

        def configure_server(api)
          unless api.respond_to?(:available_locales=) && api.respond_to?(:locale) && api.respond_to?(:parameter_i18n_scope=)
            raise 'HaveAPI with i18n support is required'
          end

          api.default_locale = DEFAULT_LOCALE
          api.available_locales = available_locales
          api.locale_header = LOCALE_HEADER
          api.parameter_i18n_scope = PARAMETER_SCOPE

          api.locale do |current_user:, default_locale:, **_|
            current_user&.language&.code || default_locale
          end
        end

        def message(key, default: nil, **values)
          HaveAPI.message(scoped_key(key), default:, **values)
        end

        def t(key, default: nil, **values)
          HaveAPI.t(scoped_key(key), default:, **values)
        end

        def locale_dir
          File.expand_path('locales', __dir__)
        end

        def external_locale_dir
          root =
            if VpsAdmin::API.respond_to?(:root)
              VpsAdmin::API.root
            else
              File.expand_path('../../..', __dir__)
            end

          File.join(root, 'config', 'locales')
        end

        def locale_paths
          [
            Dir[File.join(locale_dir, '*.yml')],
            Dir[File.join(external_locale_dir, '*.yml')]
          ].flatten
        end

        def available_locales
          locales = locale_paths.map do |path|
            File.basename(path, '.yml').to_sym
          end.uniq
          other_locales = locales.reject { |locale| locale == DEFAULT_LOCALE }.sort
          [DEFAULT_LOCALE] + other_locales
        end

        private

        def scoped_key(key)
          key = key.to_s
          key.start_with?('vpsadmin.') ? key : "vpsadmin.#{key}"
        end
      end
    end
  end
end

VpsAdmin::API::I18n.setup
