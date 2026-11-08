# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZone::DestroyUser do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_transfer_host_ip
    network = create_private_network!(
      location: SpecSeed.location,
      purpose: :vps
    )
    ip = create_ipv4_address_in_network!(
      network: network,
      location: SpecSeed.location,
      user: user
    )

    ip.host_ip_addresses.take!
  end

  it 'confirms path-state deletion with the server zone' do
    zone = create_dns_zone!(user: user, source: :external_source, email: nil)
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node),
      zone_type: :secondary_type
    )
    transfer = create_dns_zone_transfer!(
      dns_zone: zone,
      host_ip_address: create_transfer_host_ip,
      peer_type: :primary_type
    )
    state = DnsServerZonePrimaryTransferState.create!(
      dns_server_zone: server_zone,
      dns_zone_transfer: transfer,
      configuration_generation: server_zone.primary_transfer_configuration_generation,
      last_event_key: SecureRandom.hex(32),
      status: :success,
      last_attempt_kind: :ixfr_probe,
      last_attempt_at: Time.current,
      last_success_at: Time.current
    )

    chain, = described_class.fire(zone)

    state_confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'DnsServerZonePrimaryTransferState' && row.row_pks == { 'id' => state.id }
    end
    expect(state_confirmation.confirm_type).to eq('just_destroy_type')
  end
end
