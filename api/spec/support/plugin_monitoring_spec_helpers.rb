# frozen_string_literal: true

module PluginMonitoringSpecHelpers
  def build_monitor(name, **opts)
    defaults = {
      query: -> { [] },
      value: ->(obj) { obj },
      check: ->(_obj, value) { value ? true : false }
    }

    VpsAdmin::API::Plugins::Monitoring::Monitor.new(name, defaults.merge(opts))
  end
end

RSpec.configure do |config|
  config.include PluginMonitoringSpecHelpers
end
