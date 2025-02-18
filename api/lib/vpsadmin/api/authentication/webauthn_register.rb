require 'erb'

module VpsAdmin::API
  class Authentication::WebauthnRegister
    def self.run(user, params)
      new(user).run(params)
    end

    def initialize(user)
      @user = user
      @template ||= ERB.new(
        File.read(File.join(__dir__, 'webauthn_register.erb')),
        trim_mode: '-'
      )
    end

    def run(params)
      [200, { 'content-type' => 'text/html' }, render(params)]
    end

    protected

    def render(params)
      access_token = params['access_token']
      redirect_uri = params['redirect_uri']
      logo_url = ::SysConfig.get(:core, :logo_url)

      @template.result(binding)
    end
  end
end
