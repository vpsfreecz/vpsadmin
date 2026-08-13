# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::DnsTransferLog do
  let(:supervisor) { described_class.new(nil, SpecSeed.node) }
  let(:base_time) { Time.utc(2026, 8, 13, 12, 0, 0) }

  def create_path!
    zone = create_dns_zone!(
      user: SpecSeed.user,
      source: :external_source,
      email: nil
    )
    zone.update_columns(
      primary_transfer_tracking_started_at: base_time - 1.hour,
      primary_transfer_generation: SecureRandom.uuid
    )
    server = create_dns_server!(
      node: SpecSeed.node,
      name: "dns-probe-#{SecureRandom.hex(3)}",
      ipv4_addr: '192.0.2.10',
      user_dns_zone_type: :secondary_type
    )
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: server,
      zone_type: :secondary_type
    )
    server_zone.update_column(:created_at, base_time - 1.hour)

    network = SpecSeed.network_v4
    octet = IpAddress.where(network:).count + 120
    ip = "192.0.2.#{octet}"
    ip_address = IpAddress.create!(
      network:,
      ip_addr: ip,
      prefix: network.split_prefix,
      size: 1,
      user: zone.user
    )
    host_ip = HostIpAddress.create!(
      ip_address:,
      ip_addr: ip,
      user_created: true
    )
    transfer = DnsZoneTransfer.create!(
      dns_zone: zone,
      host_ip_address: host_ip,
      peer_type: :primary_type,
      confirmed: DnsZoneTransfer.confirmed(:confirmed)
    )
    transfer.update_column(:created_at, base_time - 1.hour)
    [server_zone, transfer]
  end

  def event(server_zone, transfer, attrs = {})
    status = attrs.fetch('status', 'failed')
    {
      'name' => server_zone.dns_zone.name,
      'dns_server_zone_id' => server_zone.id,
      'dns_zone_transfer_id' => transfer&.id,
      'configuration_generation' =>
        server_zone.primary_transfer_configuration_generation,
      'time' => base_time.to_i,
      'status' => status,
      'attempt_kind' => attrs.fetch('attempt_kind', 'ixfr_probe'),
      'failure_class' => status == 'failed' ? 'primary' : nil,
      'reason_code' => status == 'failed' ? 'refused' : nil,
      'reason' => status == 'failed' ? 'The primary refused the transfer' : nil,
      'primary_addr' => transfer&.ip_addr,
      'primary_serial' => 100,
      'secondary_serial' => 100,
      'message' => status == 'failed' ? 'REFUSED' : 'Transfer readiness confirmed',
      'raw_message' => nil,
      'source_cursor' => nil,
      'event_key' => SecureRandom.hex(32)
    }.merge(attrs)
  end

  def save(event)
    supervisor.send(:save_event, event)
  end

  it 'requires the coordinated new event envelope' do
    server_zone, transfer = create_path!

    expect do
      save(event(server_zone, transfer).except('configuration_generation'))
      save(event(server_zone, transfer).except('dns_server_zone_id'))
    end.not_to change(DnsServerZoneTransferLog, :count)
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
  end

  it 'rejects events after a server zone is marked for destruction' do
    server_zone, transfer = create_path!
    allow(supervisor).to receive(:find_dns_server_zone).and_return(server_zone)
    server_zone.update!(confirmed: DnsServerZone.confirmed(:confirm_destroy))

    expect { save(event(server_zone, transfer)) }
      .not_to change(DnsServerZoneTransferLog, :count)
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
  end

  it 'ignores an event when its server zone disappears before locking' do
    server_zone, transfer = create_path!
    allow(supervisor).to receive(:find_dns_server_zone).and_return(server_zone)
    server_zone.delete

    expect { save(event(server_zone, transfer)) }
      .not_to change(DnsServerZoneTransferLog, :count)
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
  end

  it 'cascades event data when pending server-zone creation rolls back' do
    server_zone, transfer = create_path!
    server_zone.update!(confirmed: DnsServerZone.confirmed(:confirm_create))
    save(event(server_zone, transfer))
    expect(DnsServerZoneTransferLog.count).to eq(1)
    expect(DnsServerZonePrimaryTransferState.count).to eq(1)

    server = server_zone.dns_server
    zone = server_zone.dns_zone
    server_zone.delete
    expect(DnsServerZoneTransferLog.count).to eq(0)
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)

    replacement = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: server,
      zone_type: :secondary_type
    )
    replacement.update_column(:created_at, base_time - 1.hour)
    save(event(replacement, transfer, 'event_key' => SecureRandom.hex(32)))
    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      dns_server_zone: replacement,
      dns_zone_transfer: transfer
    )
  end

  it 'cascades state and detaches history when pending primary creation rolls back' do
    server_zone, transfer = create_path!
    transfer.update!(confirmed: DnsZoneTransfer.confirmed(:confirm_create))
    save(event(server_zone, transfer))
    log = DnsServerZoneTransferLog.last
    expect(DnsServerZonePrimaryTransferState.count).to eq(1)

    zone = transfer.dns_zone
    host_ip = transfer.host_ip_address
    transfer.delete
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
    expect(log.reload.dns_zone_transfer_id).to be_nil

    replacement = DnsZoneTransfer.create!(
      dns_zone: zone,
      host_ip_address: host_ip,
      peer_type: :primary_type,
      confirmed: DnsZoneTransfer.confirmed(:confirmed)
    )
    replacement.update_column(:created_at, base_time - 1.hour)
    save(event(server_zone, replacement, 'event_key' => SecureRandom.hex(32)))
    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      dns_server_zone: server_zone,
      dns_zone_transfer: replacement
    )
  end

  it 'stores a probe failure and starts path continuity' do
    server_zone, transfer = create_path!
    save(event(server_zone, transfer))

    log = DnsServerZoneTransferLog.last
    state = DnsServerZonePrimaryTransferState.last
    expect(log).to have_attributes(
      dns_server_zone: server_zone,
      dns_zone_transfer: transfer,
      status: 'failed',
      attempt_kind: 'ixfr_probe',
      failure_class: 'primary'
    )
    expect(state).to have_attributes(
      status: 'failed',
      failure_class: 'primary',
      failed_since: base_time,
      last_failure_at: base_time,
      reason_code: 'refused',
      alert_eligible_at: nil
    )
  end

  it 'does not grow logs for routine successful probes' do
    server_zone, transfer = create_path!

    expect do
      3.times do |i|
        save(event(
               server_zone,
               transfer,
               'status' => 'success',
               'time' => (base_time + i.hours).to_i
             ))
      end
    end.not_to change(DnsServerZoneTransferLog, :count)

    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      status: 'success',
      last_attempt_at: base_time + 2.hours,
      last_success_at: base_time + 2.hours
    )
  end

  it 'makes an explicit failure alertable only after continuous probe evidence' do
    server_zone, transfer = create_path!
    save(event(server_zone, transfer))
    state = DnsServerZonePrimaryTransferState.last
    state.update_column(:last_failure_at, base_time + 25.minutes)

    save(event(
           server_zone,
           transfer,
           'time' => (base_time + 30.minutes).to_i
         ))

    expect(state.reload).to have_attributes(
      failed_since: base_time,
      last_failure_at: base_time + 30.minutes,
      alert_eligible_at: base_time + 30.minutes
    )
    expect(DnsServerZoneTransferLog.count).to eq(2)
  end

  it 'keeps hourly full-validation failures continuous through their slower cadence' do
    server_zone, transfer = create_path!
    invalid_zone = event(
      server_zone,
      transfer,
      'attempt_kind' => 'axfr_probe',
      'reason_code' => 'invalid_zone',
      'reason' => 'The transferred zone contains errors and was rejected',
      'message' => 'zone validation failed'
    )
    save(invalid_zone)
    save(invalid_zone.merge(
           'time' => (base_time + 1.hour).to_i,
           'event_key' => SecureRandom.hex(32)
         ))

    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      failed_since: base_time,
      last_failure_at: base_time + 1.hour,
      alert_eligible_at: base_time + 30.minutes
    )
  end

  it 'restarts slow full-validation continuity after its cadence margin' do
    server_zone, transfer = create_path!
    protocol_error = event(
      server_zone,
      transfer,
      'attempt_kind' => 'axfr_probe',
      'reason_code' => 'protocol_error',
      'reason' => 'The primary returned an invalid transfer response',
      'message' => 'malformed transfer response'
    )
    save(protocol_error)
    restart_at = base_time + 76.minutes
    save(protocol_error.merge(
           'time' => restart_at.to_i,
           'event_key' => SecureRandom.hex(32)
         ))

    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      failed_since: restart_at,
      last_failure_at: restart_at,
      alert_eligible_at: nil
    )
  end

  it 'requires network observations to span 24 hours' do
    server_zone, transfer = create_path!
    network_failure = event(
      server_zone,
      transfer,
      'failure_class' => 'network',
      'reason_code' => 'timeout',
      'reason' => 'The primary did not respond'
    )
    save(network_failure)
    state = DnsServerZonePrimaryTransferState.last
    state.update_column(:last_failure_at, base_time + 23.hours + 55.minutes)

    save(network_failure.merge(
           'time' => (base_time + 24.hours).to_i,
           'event_key' => SecureRandom.hex(32)
         ))

    expect(state.reload.alert_eligible_at).to eq(base_time + 24.hours)
    expect(DnsServerZonePrimaryTransferState.alert_eligible_at(base_time + 24.hours)).to include(state)
  end

  it 'transitions once from a primary error to a bounded continuous network failure' do
    server_zone, transfer = create_path!
    save(event(server_zone, transfer))
    network_failure = event(
      server_zone,
      transfer,
      'time' => (base_time + 1.minute).to_i,
      'failure_class' => 'network',
      'reason_code' => 'timeout',
      'reason' => 'The primary did not respond',
      'message' => 'timed out'
    )
    save(network_failure)
    state = DnsServerZonePrimaryTransferState.last
    state.update_column(:last_failure_at, base_time + 24.hours)
    save(network_failure.merge(
           'time' => (base_time + 24.hours + 1.minute).to_i,
           'event_key' => SecureRandom.hex(32)
         ))
    save(network_failure.merge(
           'time' => (base_time + 24.hours + 6.minutes).to_i,
           'event_key' => SecureRandom.hex(32)
         ))

    expect(DnsServerZoneTransferLog.count).to eq(3)
    expect(state.reload).to have_attributes(
      status: 'failed',
      failure_class: 'network',
      reason_code: 'timeout',
      failed_since: base_time + 1.minute,
      alert_eligible_at: base_time + 24.hours + 1.minute,
      last_attempt_at: base_time + 24.hours + 6.minutes
    )
  end

  it 'stores only transitions for nonactionable local probe diagnostics' do
    server_zone, transfer = create_path!
    local_failure = event(
      server_zone,
      transfer,
      'failure_class' => 'local',
      'reason_code' => 'probe_limit',
      'reason' => 'The probe reached a local limit',
      'message' => 'dig is unavailable'
    )

    3.times do |i|
      save(local_failure.merge(
             'time' => (base_time + i.minutes).to_i,
             'event_key' => SecureRandom.hex(32)
           ))
    end

    expect(DnsServerZoneTransferLog.count).to eq(1)
    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      status: 'unknown',
      last_attempt_at: base_time + 2.minutes,
      last_attempt_kind: 'ixfr_probe'
    )
  end

  it 'restarts continuity after an observation gap' do
    server_zone, transfer = create_path!
    save(event(server_zone, transfer))

    save(event(
           server_zone,
           transfer,
           'time' => (base_time + 31.minutes).to_i,
           'event_key' => SecureRandom.hex(32)
         ))

    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      failed_since: base_time + 31.minutes,
      alert_eligible_at: nil
    )
  end

  it 'allows a cheap readiness probe to recover access and network errors' do
    server_zone, transfer = create_path!
    save(event(server_zone, transfer))

    expect do
      save(event(
             server_zone,
             transfer,
             'status' => 'success',
             'time' => (base_time + 5.minutes).to_i
           ))
    end.to change(DnsServerZoneTransferLog, :count).by(1)

    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      status: 'success',
      failure_class: nil,
      failed_since: nil,
      last_success_at: base_time + 5.minutes
    )
  end

  it 'requires a validated AXFR or real transfer to recover invalid content' do
    server_zone, transfer = create_path!
    invalid = event(
      server_zone,
      transfer,
      'reason_code' => 'invalid_zone',
      'reason' => 'The zone is invalid'
    )
    save(invalid)
    save(event(
           server_zone,
           transfer,
           'status' => 'success',
           'time' => (base_time + 5.minutes).to_i
         ))
    expect(DnsServerZonePrimaryTransferState.last).to be_failed

    save(event(
           server_zone,
           transfer,
           'status' => 'success',
           'attempt_kind' => 'axfr_probe',
           'time' => (base_time + 10.minutes).to_i,
           'event_key' => SecureRandom.hex(32)
         ))
    expect(DnsServerZonePrimaryTransferState.last).to be_success
  end

  it 'keeps peer BIND diagnostics out of user-primary state' do
    server_zone, _transfer = create_path!
    peer_event = event(
      server_zone,
      nil,
      'attempt_kind' => 'transfer',
      'primary_addr' => '192.0.2.250',
      'configuration_generation' => nil
    )

    expect { save(peer_event) }.to change(DnsServerZoneTransferLog, :count).by(1)
    expect(DnsServerZoneTransferLog.last.dns_zone_transfer).to be_nil
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
  end

  it 'rejects a stale configuration generation before storing user history' do
    server_zone, transfer = create_path!

    expect do
      save(event(server_zone, transfer, 'configuration_generation' => SecureRandom.hex(32)))
    end.not_to change(DnsServerZoneTransferLog, :count)
    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
  end

  it 'lets a same-second positive observation win an inverted delivery' do
    server_zone, transfer = create_path!
    success = event(
      server_zone,
      transfer,
      'status' => 'success',
      'event_key' => 'z-success'
    )
    failure = event(server_zone, transfer, 'event_key' => 'a-failure')

    save(success)
    save(failure)

    expect(DnsServerZonePrimaryTransferState.last).to be_success
    expect(DnsServerZoneTransferLog.count).to eq(0)
  end

  it 'retains a late BIND diagnostic without rolling path state backward' do
    server_zone, transfer = create_path!
    save(event(
           server_zone,
           transfer,
           'status' => 'success',
           'time' => (base_time + 1.hour).to_i
         ))

    save(event(
           server_zone,
           transfer,
           'attempt_kind' => 'transfer',
           'raw_message' => 'transfer failed: REFUSED'
         ))

    expect(DnsServerZonePrimaryTransferState.last).to have_attributes(
      status: 'success',
      last_attempt_at: base_time + 1.hour
    )
    expect(DnsServerZoneTransferLog.last).to have_attributes(
      status: 'failed',
      attempt_kind: 'transfer',
      raw_message: 'transfer failed: REFUSED'
    )
  end

  it 'updates real-transfer history independently from serving status' do
    server_zone, transfer = create_path!
    save(event(
           server_zone,
           transfer,
           'status' => 'success',
           'attempt_kind' => 'transfer',
           'serial' => 101
         ))

    expect(server_zone.reload).to have_attributes(
      last_transfer_status: 'success',
      last_transfer_serial: 101
    )
    expect(DnsServerZonePrimaryTransferState.last).to be_success
  end
end
