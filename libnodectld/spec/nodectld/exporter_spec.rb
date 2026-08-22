# frozen_string_literal: true

require 'spec_helper'
require 'prometheus/client/formats/text'
require 'nodectld/exporter'
require 'nodectld/vps_autostart_status'

class VpsAutostartExporterDaemon
  attr_reader :console, :queues, :start_time, :vps_status

  def initialize(vps_autostart_status)
    @console = Struct.new(:stats).new({})
    @queues = {}
    @start_time = Time.now
    @vps_status = Struct.new(:vps_autostart_status).new(vps_autostart_status)
  end

  def initialized?
    true
  end

  def run?
    true
  end

  def paused?
    false
  end

  def chain_blockers
    yield nil
  end
end

RSpec.describe NodeCtld::Exporter do
  def container(id:, state:, autostart:)
    Struct.new(:id, :pool, :state, :autostart).new(
      id.to_s,
      'tank',
      state,
      autostart
    )
  end

  def render(status)
    registry = Prometheus::Client::Registry.new
    exporter = described_class.new(VpsAutostartExporterDaemon.new(status))
    metrics = exporter.send(:setup_metrics, registry)
    exporter.send(:collect_metrics, metrics)
    Prometheus::Client::Formats::Text.marshal(registry)
  end

  it 'exports per-VPS availability, reason, aggregate and drift metrics' do
    status = NodeCtld::VpsAutostartStatus.new
    status.update(
      [
        {
          'id' => 101,
          'pool_fs' => 'tank/private',
          'autostart_enable' => true
        }
      ],
      [container(id: 101, state: 'stopped', autostart: false)],
      now: Time.at(1_234)
    )

    output = render(status)

    expect(output).to include('nodectld_vps_autostart_check_success 1.0')
    expect(output).to include(
      'nodectld_vps_autostart_check_last_success_timestamp_seconds 1234.0'
    )
    expect(output).to include(
      'nodectld_vps_autostart_expected{pool="tank"} 1.0'
    )
    expect(output).to include(
      'nodectld_vps_autostart_unsatisfied{pool="tank",vps_id="101"} 1.0'
    )
    expect(output).to include(
      'nodectld_vps_autostart_unsatisfied_reason{' \
      'pool="tank",vps_id="101",reason="stopped"} 1.0'
    )
    expect(output).to include(
      'nodectld_vps_autostart_unsatisfied_count{' \
      'pool="tank",reason="stopped"} 1.0'
    )
    expect(output).to include(
      'nodectld_vps_autostart_mismatch{' \
      'pool="tank",vps_id="101",vpsadmin="enabled",osctld="disabled"} 1.0'
    )
  end

  it 'does not export stale per-VPS metrics after a failed check' do
    status = NodeCtld::VpsAutostartStatus.new
    status.update(
      [
        {
          'id' => 101,
          'pool_fs' => 'tank/private',
          'autostart_enable' => true
        }
      ],
      []
    )
    status.failed

    output = render(status)

    expect(output).to include('nodectld_vps_autostart_check_success 0.0')
    expect(output).not_to include('nodectld_vps_autostart_unsatisfied{')
    expect(output).not_to include('nodectld_vps_autostart_unsatisfied_reason{')
    expect(output).not_to include('nodectld_vps_autostart_mismatch{')
  end
end
