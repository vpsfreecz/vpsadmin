require 'spec_helper'

RSpec.describe TransactionChains::Ip::Disown do
  around { |example| with_current_context { example.run } }

  before do
    unlock_transaction_signer!
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'combines mixed cleanup and plain allocations into one deferred quota change' do
    ips = Array.new(3) { create_ip_address!(user: SpecSeed.user) }
    ips.first.host_ip_addresses.first.update!(user_created: true)
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    usage = config.ipv4
    chain, = described_class.fire(ips:, defer: true)
    expect(ips.map { |ip| ip.reload.user_id }).to eq([SpecSeed.user.id] * 3)
    expect(config.reload.ipv4).to eq(usage)
    edits = confirmations_for(chain).select { |row| row.confirm_type == 'edit_after_type' }
    expect(edits.map(&:transaction_id).uniq).to eq([chain.transactions.maximum(:id)])
    expect(edits.count { |row| row.class_name == 'IpAddress' }).to eq(3)
    totals = edits.select { |row| row.class_name == 'ClusterResourceUse' }
    expect(totals.map { |row| row.attr_changes.fetch('value') }).to eq([usage - 3])
  end

  it 'keeps owner, charge environment and resource totals separate' do
    private_network = create_private_network!(purpose: :vps)
    ips = [
      create_ip_address!(user: SpecSeed.user),
      create_ip_address!(user: SpecSeed.other_user),
      create_ip_address!(user: SpecSeed.user, network: private_network, addr: private_network.address.sub(/0$/, '10')),
      create_ip_address!(user: SpecSeed.user, network: SpecSeed.network_v6, addr: '2001:db8::30')
    ]
    # The charge belongs to the registration environment, even when a network
    # is also available elsewhere.
    LocationNetwork.create!(network: SpecSeed.network_v4, location: SpecSeed.other_location, autopick: true, userpick: true)
    ips << create_ip_address!(user: SpecSeed.user, location: SpecSeed.other_location)
    before = ips.to_h do |ip|
      config = ip.user.environment_user_configs.find_by!(environment: ip.charged_environment)
      [ip.id, config.public_send(ip.cluster_resource)]
    end
    chain, = described_class.fire(ips:, defer: true)
    totals = confirmations_for(chain).select { |row| row.class_name == 'ClusterResourceUse' }
    expect(totals.size).to eq(5)
    totals.each do |row|
      usage = ClusterResourceUse.find(row.row_pks.fetch('id'))
      ip = ips.find do |entry|
        quota = usage.user_cluster_resource
        entry.user_id == quota.user_id && entry.charged_environment_id == quota.environment_id &&
          entry.cluster_resource.to_s == quota.cluster_resource.name
      end
      expect(row.attr_changes.fetch('value')).to eq(before.fetch(ip.id) - ip.size.to_i)
    end
  end
end
