# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Export::AddHosts do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'adds only IPv4 hosts and confirms each host creation' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "export-hosts-#{SecureRandom.hex(4)}"
    )
    export, = create_export_for_dataset!(dataset_in_pool: dip)
    ipv4 = create_vps_ip_address!(user: user, pool: pool)
    ipv6 = create_ip_address!(
      network: SpecSeed.network_v6,
      location: SpecSeed.other_location,
      addr: "2001:db8::#{IpAddress.maximum(:id).to_i + 20}"
    )
    hosts = [
      ExportHost.new(export: export, ip_address: ipv4, rw: true, sync: true, subtree_check: false, root_squash: false),
      ExportHost.new(export: export, ip_address: ipv6, rw: true, sync: true, subtree_check: false, root_squash: false)
    ]

    chain, created_hosts = described_class.fire(export, hosts)

    expect(tx_classes(chain)).to eq([Transactions::Export::AddHosts])
    expect(created_hosts.map(&:ip_address_id)).to eq([ipv4.id])
    expect(chain.locks.map { |row| [row.resource, row.row_id] }).to include(['IpAddress', ipv4.id])
    expect(tx_payload(chain, Transactions::Export::AddHosts).fetch('hosts').map { |host| host.fetch('address') }).to eq(
      [ipv4.to_s]
    )
    expect(confirmations_for(chain).select { |row| row.class_name == 'ExportHost' }.map(&:confirm_type)).to eq(
      ['just_create_type']
    )
  end

  context 'with an assignment pending confirmation' do
    let(:fixture) { create_netif_vps_fixture!(user: user) }
    let(:ip) { create_ip_address! }
    let(:export) { create_export_for_dataset!(dataset_in_pool: fixture[:dataset_in_pool]).first }
    let(:host) do
      ExportHost.new(export: export, ip_address: ip, rw: true, sync: true,
                     subtree_check: false, root_squash: false)
    end

    before { ip.network_interface = fixture[:netif] }

    it 'preserves the intended assignment when the caller explicitly passes a reserved IP' do
      chain = build_transaction_chain!
      chain.lock(ip)
      created = chain.use_chain(described_class, args: [export, [host]], kwargs: { reserved_ips: true })
      expect(created.map(&:ip_address_id)).to eq([ip.id])
      expect(IpAddress.find(ip.id).network_interface_id).to be_nil
      expect(ip.network_interface_id).to eq(fixture[:netif].id)
    end

    it 'requires a real chain reservation before accepting pending state' do
      chain = build_transaction_chain!
      expect do
        chain.use_chain(described_class, args: [export, [host]], kwargs: { reserved_ips: true })
      end.to raise_error(ResourceLocked, /not reserved/)
      expect(host).not_to be_persisted
    end

    it 'reloads public grant inputs even if the chain already reserved the IP' do
      chain = build_transaction_chain!
      chain.lock(ip)
      expect { chain.use_chain(described_class, args: [export, [host]]) }
        .to raise_error(ActiveRecord::RecordInvalid, /ownership or assignment changed/)
      expect(host).not_to be_persisted
    end
  end
end
