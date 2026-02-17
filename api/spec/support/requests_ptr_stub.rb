# frozen_string_literal: true

module SpecRequestsPtrStub
  module_function

  def install!
    return if installed?
    return if ENV['VPSADMIN_PLUGINS'].to_s.strip.downcase == 'none'
    return unless defined?(::UserRequest)
    return if defined?(SpecPlugins) && !SpecPlugins.enabled?(:requests)

    unless ::UserRequest.ancestors.include?(SpecRequestsPtrStub)
      ::UserRequest.prepend(SpecRequestsPtrStub)
    end

    @installed = true
  end

  def installed?
    @installed
  end

  private

  def get_ptr(ip)
    "ptr-#{ip}"
  end
end

RSpec.configure do |config|
  config.append_before(:suite) do
    SpecRequestsPtrStub.install!
  end

  config.before do
    SpecRequestsPtrStub.install! unless SpecRequestsPtrStub.installed?
  end
end
