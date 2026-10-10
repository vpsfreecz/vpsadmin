require 'spec_helper'

RSpec.describe NetworkInterface, :no_transaction do
  let(:owned_records) { [] }

  around do |example|
    with_current_context(user: SpecSeed.user) do |session|
      owned_records << session
      example.run
    end
  ensure
    primary_error = $! || example.exception

    begin
      cleanup_owned_records!
    rescue StandardError
      raise unless primary_error

      warn 'Network interface ownership fixture cleanup failed after a primary error'
    end
  end

  before { unlock_transaction_signer! }

  # These examples need only committed ownership rows, without shared storage,
  # node-status or quota changes.
  def create_netif_vps_fixture!(user:)
    records = []
    fixture = ActiveRecord::Base.transaction do
      userns_map = create_user_namespace_map!(user:)
      vps = create_vps_for_dataset!(user:, node: SpecSeed.node, dataset_in_pool: nil,
                                    user_namespace_map: userns_map)
      netif = create_network_interface!(vps, name: 'eth0')
      records.push(userns_map.user_namespace, userns_map, vps,
                   *ObjectState.where(class_name: 'Vps', row_id: vps.id).to_a, netif)
      { vps:, netif: }
    end
    owned_records.concat(records)
    fixture
  end

  def create_ip_address!(user:, network_interface:)
    records = []
    ip = ActiveRecord::Base.transaction do
      network = create_private_network!(purpose: :vps, split_prefix: 24)
      created = IpAddress.register(
        IPAddress.parse("#{network.address}/#{network.split_prefix}"),
        network:, location: SpecSeed.location, user:, prefix: network.split_prefix,
        size: 1, allocate: false
      )
      created.update!(network_interface:) if network_interface
      records.push(network, *network.location_networks.to_a, created,
                   *created.host_ip_addresses.to_a)
      created
    end
    owned_records.concat(records)
    ip
  end

  def cleanup_owned_records!
    ActiveRecord::Base.transaction do
      owned_records.reverse_each do |record|
        PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).delete_all
        record.class.where(id: record.id).delete_all
      end
    end
  end

  def commit_ownership_transfer(&)
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.transaction(&)
      end
    end
    worker.value
  ensure
    worker&.join(25) || worker&.kill&.join
  end

  %i[add_route remove_route add_host_address remove_host_address].each do |operation|
    it "rejects #{operation} after the authorized VPS is transferred before locking" do
      fixture = create_netif_vps_fixture!(user: SpecSeed.user)
      ip = create_ip_address!(user: SpecSeed.user,
                              network_interface: operation == :add_route ? nil : fixture[:netif])
      host = ip.host_ip_addresses.first
      host.update!(order: 0) if operation == :remove_host_address
      target = operation.to_s.include?('host') ? host : ip
      original_interface = ip.network_interface_id
      original_order = host.order
      selected_vps = fixture[:netif].vps
      selected_ip = operation.to_s.include?('host') ? host.ip_address : ip

      expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
      expect(selected_vps.user_id).to eq(SpecSeed.user.id)
      expect(selected_ip.user_id).to eq(SpecSeed.user.id)

      # Commit the transfer before the public operation can acquire row locks.
      # Keep the selected VPS and IP stale for the real actor refresh.
      commit_ownership_transfer do
        Vps.where(id: fixture[:vps].id).update_all(user_id: SpecSeed.other_user.id)
        IpAddress.where(id: ip.id).update_all(user_id: SpecSeed.other_user.id)
      end

      expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
      expect(Vps.where(id: selected_vps.id).pick(:user_id)).to eq(SpecSeed.other_user.id)
      expect(IpAddress.where(id: selected_ip.id).pick(:user_id)).to eq(SpecSeed.other_user.id)
      expect(selected_vps.user_id).to eq(SpecSeed.user.id)
      expect(selected_ip.user_id).to eq(SpecSeed.user.id)

      expect do
        if operation == :add_route
          fixture[:netif].add_route(ip, safe: true)
        else
          fixture[:netif].public_send(operation, target)
        end
      end.to raise_error(VpsAdmin::API::Exceptions::IpAddressNotOwned)
      expect(ip.reload.user_id).to eq(SpecSeed.other_user.id)
      expect(ip.network_interface_id).to eq(original_interface)
      expect(host.reload.order).to eq(original_order)
    end
  end
end
