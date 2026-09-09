require 'spec_helper'

RSpec.describe NetworkInterface do
  around { |example| with_current_context(user: SpecSeed.user) { example.run } }

  before { unlock_transaction_signer! }

  {
    add_route: TransactionChains::NetworkInterface::AddRoute,
    remove_route: TransactionChains::NetworkInterface::DelRoute,
    add_host_address: TransactionChains::NetworkInterface::AddHostIp,
    remove_host_address: TransactionChains::NetworkInterface::DelHostIp
  }.each do |operation, chain_class|
    it "rejects #{operation} after the authorized VPS is transferred before locking" do
      fixture = create_netif_vps_fixture!(user: SpecSeed.user)
      ip = create_ip_address!(user: SpecSeed.user,
                              network_interface: operation == :add_route ? nil : fixture[:netif])
      host = ip.host_ip_addresses.first
      host.update!(order: 0) if operation == :remove_host_address
      target = operation.to_s.include?('host') ? host : ip
      original_interface = ip.network_interface_id
      original_order = host.order

      # The public model precheck sees the original tenant. The chain receives
      # the same stale objects after a completed ownership transfer.
      allow(chain_class).to receive(:fire2).and_wrap_original do |original, **kwargs|
        Vps.where(id: fixture[:vps].id).update_all(user_id: SpecSeed.other_user.id)
        IpAddress.where(id: ip.id).update_all(user_id: SpecSeed.other_user.id)
        original.call(**kwargs)
      end

      expect { fixture[:netif].public_send(operation, target) }
        .to raise_error(VpsAdmin::API::Exceptions::IpAddressNotOwned)
      expect(ip.reload.user_id).to eq(SpecSeed.other_user.id)
      expect(ip.network_interface_id).to eq(original_interface)
      expect(host.reload.order).to eq(original_order)
    end
  end
end
