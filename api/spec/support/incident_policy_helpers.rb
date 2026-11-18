require 'active_support/testing/time_helpers'

module IncidentPolicyHelpers
  include ActiveSupport::Testing::TimeHelpers

  def install_generic_incident_policy_fixture(mode: 'observe')
    declaration = IncidentEscalation::Configuration.new
    declaration.rule(:category) do
      labels en: 'Category policy'
      limits warning: 2, stop: 4
      applies_if { |ctx| ctx.report[:codename] == 'manual_abuse' }
    end
    declaration.rule(:content) do
      labels en: 'Content policy'
      limits warning: 3, stop: 6
      applies_if { |ctx| ctx.report[:text].include?('evidence') }
    end
    stub_const('IncidentEscalation::RULES', declaration.rules.freeze)
    declaration.rules.each_value do |rule|
      SysConfig.create!(category: rule.category, name: 'mode', value: mode, data_type: 'String')
    end
  end

  # Explicit source fixture; the application has no implicit policy registry.
  def install_incident_policy_fixture
    declaration = IncidentEscalation::Configuration.new
    declaration.rule(:oomd) do
      labels en: 'VPS memory-pressure incidents', cs: 'Incidenty přetížení paměti VPS'
      limits warning: 5, stop: 10
      templates warning: :vps_memory_pressure_warning, stopped: :vps_memory_pressure_stopped
      applies_if do |ctx|
        ctx.report[:codename] == 'oomd' && ctx.source[:kind] == 'node_vps_event' &&
          !ctx.source[:key].nil? && !ctx.source[:node_id].nil? &&
          ctx.source[:node_id] == ctx.vps[:node_id] && %w[restart stop].include?(ctx.source[:action])
      end
    end
    stub_const('IncidentEscalation::RULES', declaration.rules.freeze)
    %w[mode warning_limit stop_limit].each do |name|
      SysConfig.find_or_create_by!(category: 'incident_policy_oomd', name:) do |row|
        row.data_type = name == 'mode' ? 'String' : 'Integer'
        row.value = name == 'mode' ? 'observe' : nil
      end
    end
  end
end

RSpec.configure { |config| config.include IncidentPolicyHelpers }
