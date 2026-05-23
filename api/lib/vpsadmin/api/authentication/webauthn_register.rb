require 'erb'
require 'json'

module VpsAdmin::API
  class Authentication::WebauthnRegister
    def self.run(user, params, access_token:)
      new(user).run(params, access_token:)
    end

    def initialize(user)
      @user = user
      @template ||= ERB.new(
        File.read(File.join(__dir__, 'webauthn_register.erb')),
        trim_mode: '-'
      )
    end

    def run(params, access_token:)
      [200, { 'content-type' => 'text/html' }, render(params, access_token:)]
    end

    protected

    def render(params, access_token:)
      redirect_uri = params['redirect_uri']
      logo_url = ::SysConfig.get(:core, :logo_url)

      @template.result(binding)
    end

    def js_string(value)
      JSON.dump(value.to_s)
          .gsub('<', '\\u003c')
          .gsub('>', '\\u003e')
          .gsub('&', '\\u0026')
          .gsub("\u2028", '\\u2028')
          .gsub("\u2029", '\\u2029')
    end
  end
end
