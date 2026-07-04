# frozen_string_literal: true

module VpsAdmin
  module API
    module I18n
      DEFAULT_LOCALE = :en
      LOCALE_HEADER = 'Accept-Language'

      class << self
        def setup
          ::I18n.load_path |= Dir[File.join(locale_dir, '*.yml')]
        end

        def configure_server(api)
          unless api.respond_to?(:available_locales=) && api.respond_to?(:locale)
            raise 'HaveAPI with i18n support is required'
          end

          api.default_locale = DEFAULT_LOCALE
          api.available_locales = available_locales
          api.locale_header = LOCALE_HEADER

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

        def available_locales
          locales = Dir[File.join(locale_dir, '*.yml')].map do |path|
            File.basename(path, '.yml').to_sym
          end
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
