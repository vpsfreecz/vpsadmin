# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'outage reports plugin metrics', requires_plugins: :outage_reports do # rubocop:disable RSpec/DescribeClass
  include OutageReportsSpecHelpers

  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def render_metrics_for(user)
    token = MetricsAccessToken.create_for!(user, 'spec_outage_')
    registry = Prometheus::Client::Registry.new
    metrics = VpsAdmin::API::Plugins::OutageReports::Metrics.new(registry, token)
    metrics.setup
    metrics.compute
    Prometheus::Client::Formats::Text.marshal(registry)
  end

  def attach_export_address!(export)
    netif = NetworkInterface.create!(
      export: export,
      kind: :veth_routed,
      name: "export#{SecureRandom.hex(3)}"
    )
    ip = IpAddress.create!(
      network: SpecSeed.network_v4,
      network_interface: netif,
      ip_addr: "192.0.2.#{rand(150..199)}",
      prefix: 32,
      size: 1
    )
    HostIpAddress.create!(ip_address: ip, ip_addr: ip.ip_addr)
  end

  it 'exports announced VPS and export outages affecting the token user' do
    user = SpecSeed.user
    outage = create_outage_with_translation!(
      {
        state: :announced,
        outage_type: :planned_outage,
        impact_type: :network,
        begins_at: Time.local(2026, 4, 1, 10, 0, 0),
        duration: 60,
        auto_resolve: true
      },
      summary: 'Network outage',
      description: 'Description'
    )
    vps = create_vps!(user: user, node: SpecSeed.node)
    export = create_export!(user: user)
    attach_export_address!(export)

    OutageVps.create!(
      outage: outage,
      vps: vps,
      user: user,
      environment: vps.node.location.environment,
      location: vps.node.location,
      node: vps.node,
      direct: true
    )
    OutageExport.create!(
      outage: outage,
      export: export,
      user: user,
      environment: export.dataset_in_pool.pool.node.location.environment,
      location: export.dataset_in_pool.pool.node.location,
      node: export.dataset_in_pool.pool.node
    )
    OutageUser.create!(outage: outage, user: user, vps_count: 1, export_count: 1)

    output = render_metrics_for(user)

    expect(output).to include('spec_outage_vps_outage_report')
    expect(output).to include('spec_outage_export_outage_report')
    expect(output).to include('outage_summary_en="Network outage"')
    expect(output).to include('outage_summary_cs=""')
    expect(output).to include("vps_id=\"#{vps.id}\"")
    expect(output).to include("export_id=\"#{export.id}\"")

    other_output = render_metrics_for(SpecSeed.other_user)
    expect(other_output).not_to include('spec_outage_vps_outage_report{')
    expect(other_output).not_to include('spec_outage_export_outage_report{')
  end
end
