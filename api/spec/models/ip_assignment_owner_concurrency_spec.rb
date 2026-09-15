require 'spec_helper'
require 'timeout'

RSpec.describe IpAddress, :no_transaction do
  let(:fixture) { {} }

  def connection_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context(user: SpecSeed.user) do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
  end

  before do
    unlock_transaction_signer!
    connection_thread do
      # Only the ownership relation is needed here; no node action is queued.
      vps = create_vps_for_dataset!(user: SpecSeed.user, node: SpecSeed.node, dataset_in_pool: nil)
      fixture.merge!(vps: vps, userns_map: vps.user_namespace_map, userns: vps.user_namespace_map.user_namespace)
      netif = create_network_interface!(vps, name: 'eth0')
      fixture[:netif] = netif
      network = create_private_network!(purpose: :vps, split_prefix: 24)
      fixture[:network] = network
      ip = create_ipv4_address_in_network!(network: network, location: SpecSeed.location)
      fixture[:ip] = ip
      ip.update!(network_interface: netif)
    end.value
  end

  after do
    connection_thread do
      HostIpAddress.where(ip_address_id: fixture[:ip]&.id).delete_all
      described_class.where(id: fixture[:ip]&.id).delete_all
      NetworkInterface.where(id: fixture[:netif]&.id).delete_all
      Vps.where(id: fixture[:vps]&.id).delete_all
      UserNamespaceMap.where(id: fixture[:userns_map]&.id).delete_all
      UserNamespace.where(id: fixture[:userns]&.id).delete_all
      LocationNetwork.where(network_id: fixture[:network]&.id).delete_all
      Network.where(id: fixture[:network]&.id).delete_all
      fixture.each_value do |record|
        PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).delete_all
      end
    end.value
  end

  def after_vps_transfer
    selected = Queue.new
    resume = Queue.new
    worker = connection_thread do
      TransactionChain.transaction do
        ip = described_class.find(fixture[:ip].id)
        expect(ip.current_owner).to eq(SpecSeed.user) # Establish an older snapshot.
        selected << true
        resume.pop
        yield ip
        raise ActiveRecord::Rollback
      end
    end
    Timeout.timeout(10) { selected.pop }
    connection_thread { Vps.where(id: fixture[:vps].id).update_all(user_id: SpecSeed.other_user.id) }.value
    resume << true
    Timeout.timeout(20) { worker.value }
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
  end

  it 'denies host creation after a VPS transfer that leaves the standalone IP row unchanged' do
    after_vps_transfer do |ip|
      parts = ip.ip_addr.split('.').map(&:to_i)
      parts[-1] += 1
      addr = parts.join('.')
      expect do
        VpsAdmin::API::Operations::HostIpAddress::Create.run(ip, addr, actor: SpecSeed.user)
      end.to raise_error(VpsAdmin::API::Exceptions::OperationError,
                         VpsAdmin::API::I18n.t('errors.access_denied_lower'))
    end
    expect(fixture[:ip].host_ip_addresses.count).to eq(1)
  end

  it 'rejects a grant selected under the previous VPS owner despite an unchanged IP assignment' do
    after_vps_transfer do |ip|
      host = ExportHost.new(export: Export.new(user: SpecSeed.user), ip_address: ip)
      expect { host.lock_ip!(build_transaction_chain!) }
        .to raise_error(ActiveRecord::RecordInvalid, /ownership or assignment changed/)
      expect(host).not_to be_persisted
    end
  end

  it 'rejects DNS transfer grants after the assigned VPS changes owner' do
    after_vps_transfer do |ip|
      zone = create_dns_zone!(user: SpecSeed.user, source: :internal_source)
      transfer = DnsZoneTransfer.new(dns_zone: zone, host_ip_address: ip.host_ip_addresses.first!,
                                     peer_type: :secondary_type)
      expect { TransactionChains::DnsZoneTransfer::Create.fire(transfer) }
        .to raise_error(ActiveRecord::RecordInvalid, /does not belong to your account/)
    end
  end

  context 'when assignment policy changes after selection' do
    before do
      connection_thread { fixture[:ip].update!(network_interface: nil) }.value
    end

    def after_policy_change(change)
      selected = Queue.new
      resume = Queue.new
      worker = connection_thread do
        TransactionChain.transaction do
          ip = described_class.find(fixture[:ip].id)
          expect(ip.network.purpose).to eq('vps')
          expect(ip.network.location_networks.find_by!(location: SpecSeed.location).userpick).to be(true)
          selected << true
          resume.pop
          yield ip
          raise ActiveRecord::Rollback
        end
      end
      Timeout.timeout(10) { selected.pop }
      connection_thread(&change).value
      resume << true
      Timeout.timeout(20) { worker.value }
    ensure
      resume << true if resume
      worker&.join(25) || worker&.kill&.join
    end

    it 'rejects manual assignment after userpick is revoked' do
      after_policy_change(-> { fixture[:network].location_networks.update_all(userpick: false) }) do |ip|
        expect { fixture[:netif].add_route(ip, safe: true) }
          .to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /cannot be freely assigned/)
      end
      expect(fixture[:ip].reload.network_interface_id).to be_nil
    end

    it 'rejects manual assignment after the network becomes export-only' do
      after_policy_change(-> { fixture[:network].update!(purpose: :export) }) do |ip|
        expect { fixture[:netif].add_route(ip, safe: true) }
          .to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /cannot be assigned to a VPS/)
      end
      expect(fixture[:ip].reload.network_interface_id).to be_nil
    end

    it 'rechecks the primary location policy for a shared-network selection' do
      connection_thread do
        fixture[:secondary_locnet] = LocationNetwork.create!(
          network: fixture[:network], location: SpecSeed.other_location,
          primary: false, autopick: true, userpick: true, priority: 10
        )
      end.value

      opts = { user: SpecSeed.user, location: SpecSeed.other_location,
               address_location: SpecSeed.location, ip_v: 4, role: :private_access, purpose: :vps }
      after_policy_change(-> { fixture[:network].location_networks.where(primary: true).update_all(userpick: false) }) do |ip|
        ip.lock_current!(build_transaction_chain!)
        expect { ip.ensure_pickable!(opts) }
          .to raise_error(VpsAdmin::API::Exceptions::IpAddressInUse, /no longer available/)
      end
    end
  end
end
