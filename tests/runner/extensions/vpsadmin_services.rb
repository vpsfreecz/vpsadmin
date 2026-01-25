# frozen_string_literal: true

require 'osvm'
require 'test-runner/hook'

class VpsadminServicesMachine < OsVm::NixosMachine
  def wait_for_vpsadmin_api(timeout: @default_timeout || 300)
    wait_until_succeeds(
      "curl --silent --fail http://api.vpsadmin.test/ | grep 'API description'",
      timeout:
    )
  end
end

TestRunner::Hook.subscribe(:machine_class_for) do |machine_config|
  next unless machine_config.tags.include?('vpsadmin-services')

  VpsadminServicesMachine
end
