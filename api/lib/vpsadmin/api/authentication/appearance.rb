require 'erb'
require 'digest'
require 'json'

module VpsAdmin::API
  # Cosmetic browser state is separate from authentication and OAuth state.
  class Authentication::Appearance
    PREFERENCES = %w[light dark auto].freeze
    ASSETS = File.join(__dir__, 'assets').freeze
    I18N_KEYS = %w[label light dark auto].freeze
    LOGO_PATH = '/_auth/appearance/logo'.freeze
    IMAGE_TYPES = {
      '.png' => 'image/png',
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.svg' => 'image/svg+xml'
    }.freeze

    def self.i18n_keys
      I18N_KEYS.map { |key| "auth.appearance.#{key}" }
    end

    def self.preference(params)
      value = params[:theme] || params['theme']
      value if value.is_a?(String) && PREFERENCES.include?(value)
    end

    def self.return_theme?(params)
      (params[:theme_return] || params['theme_return']) == '1'
    end

    def self.head(preference)
      css = File.read(File.join(ASSETS, 'appearance.css'))
      script = File.read(File.join(ASSETS, 'appearance.js'))
      "<style>#{css}</style><script>#{script.sub('INITIAL_PREFERENCE', JSON.generate(preference))}</script>"
    end

    def self.controls
      labels = I18N_KEYS.to_h do |key|
        [key, Rack::Utils.escape_html(VpsAdmin::API::I18n.t("auth.appearance.#{key}"))]
      end
      ERB.new(File.read(File.join(ASSETS, 'appearance_controls.erb'))).result(binding)
    end

    def self.logo(scheme)
      return unless %w[light dark].include?(scheme)

      keys = ["#{scheme}_logo_file", 'logo_file']
      keys.each do |key|
        value = DeploymentConfig.dig('authentication', key)
        next unless value.is_a?(String)

        value = value.strip
        next unless value.start_with?('/') && !value.include?("\0")

        type = IMAGE_TYPES[File.extname(value).downcase]
        next unless type && File.file?(value) && File.readable?(value)

        return { file: value, type: }
      end
      nil
    end

    def self.register_routes(sinatra)
      appearance = self
      %w[light dark].each do |scheme|
        serve = proc do
          logo = appearance.logo(scheme)
          halt 404 unless logo

          begin
            image = File.binread(logo.fetch(:file))
          rescue SystemCallError, IOError
            halt 404
          end

          headers(
            'Content-Type' => logo.fetch(:type),
            'Content-Disposition' => 'inline',
            'X-Content-Type-Options' => 'nosniff',
            'Content-Security-Policy' => "default-src 'none'; style-src 'unsafe-inline'; sandbox; base-uri 'none'; form-action 'none'",
            'Cache-Control' => 'public, max-age=0, must-revalidate'
          )
          etag Digest::SHA256.hexdigest(image)
          headers 'Content-Length' => image.bytesize.to_s
          image
        end
        # Sinatra also registers HEAD; Rack::Head removes its response body.
        sinatra.get "#{LOGO_PATH}/#{scheme}", &serve
      end
    end

    def self.brand(scheme: nil)
      schemes = scheme ? [scheme] : %w[light dark]
      images = schemes.map do |selected|
        klass = scheme ? 'authentication-logo' : "authentication-logo authentication-logo-#{selected}"
        configured = logo(selected)
        if configured
          url = "#{LOGO_PATH}/#{selected}"
          "<img class=\"#{klass}\" src=\"#{url}\" alt=\"vpsAdmin\">"
        else
          "<span class=\"#{klass}\">#{File.read(File.join(ASSETS, 'vpsadmin.svg'))}</span>"
        end
      end
      "<div class=\"authentication-brand\">#{images.join}</div>"
    end
  end
end
