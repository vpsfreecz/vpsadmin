require 'ipaddress'

# First, this migration makes it possible to add more network interfaces
# to one VPS, IP addresses are assigned to interfaces, not VPSes.
#
# It also changes the meaning of the {IpAddress} model. {IpAddress}
# will represent routable addresses. These addresses can be routed to VPS, but
# aren't assigned to any interface. The user can either assign _any_ address
# from that network manually, or through vpsAdmin. Addresses assigned to
# interfaces are represented by the {HostIpAddress} model.
#
# This migration creates {HostIpAddress} records for every {IpAddress}
# and properly assigns them to VPS interfaces.
class VpsInterfacesAddresses < ActiveRecord::Migration
  class Vps < ActiveRecord::Base
    has_many :network_interfaces
    has_many :ip_addresses
  end

  class NetworkInterface < ActiveRecord::Base
    belongs_to :vps
    has_many :ip_addresses
    has_many :host_ip_addresses
    enum kind: %i(venet veth_bridge veth_routed)
  end

  class Network < ActiveRecord::Base
    has_many :ip_addresses
    enum role: %i(public_access private_access)
  end

  class IpAddress < ActiveRecord::Base
    belongs_to :network
    belongs_to :network_interface
    has_many :host_ip_addresses
  end

  class HostIpAddress < ActiveRecord::Base
    belongs_to :ip_address
  end

  def up
    create_table :network_interfaces do |t|
      t.references  :vps,               null: false
      t.string      :name,              null: false, limit: 30
      t.integer     :kind,              null: false
      t.string      :mac,               null: true,  limit: 17
      t.timestamps
    end

    add_index :network_interfaces, %i(vps_id name), unique: true
    add_index :network_interfaces, :vps_id
    add_index :network_interfaces, :kind
    add_index :network_interfaces, :mac, unique: true

    create_table :host_ip_addresses do |t|
      t.references  :ip_address,        null: false
      t.string      :ip_addr,           null: false, limit: 40
      t.integer     :order,             null: true
    end

    add_index :host_ip_addresses, %i(ip_address_id ip_addr), unique: true
    add_index :host_ip_addresses, :ip_address_id

    add_column :ip_addresses, :network_interface_id, :integer, null: true
    add_index :ip_addresses, :network_interface_id

    # Create one HostIpAddress for each IpAddress
    IpAddress.joins(:network).where(networks: {role: [
      Network.roles[:public_access],
      Network.roles[:private_access],
    ]}).each do |ip|
      HostIpAddress.create!(
        ip_address_id: ip.id,
        ip_addr: IPAddress.parse(ip.ip_addr).first.to_s,
        order: nil,
      )
    end

    # Create NetworkInterface for every VPS
    Vps.where('object_state < 3').each do |vps|
      netif = NetworkInterface.create!(
        vps_id: vps.id,
        name: vps.veth_name,
        kind: NetworkInterface.kinds[vps.veth_mac ? :veth_routed : :venet],
        mac: vps.veth_mac,
      )

      vps.ip_addresses.joins(:network).where(networks: {role: [
        Network.roles[:public_access],
        Network.roles[:private_access],
      ]}).each do |ip|
        ip.update!(network_interface_id: netif.id)
        host_ip = ip.host_ip_addresses.take!
        host_ip.update!(order: ip.order)
      end
    end

    remove_column :vpses, :veth_name
    remove_column :vpses, :veth_mac
    remove_column :ip_addresses, :vps_id
  end

  def down
    add_column :vpses, :veth_name, :string, limit: 30, null: false, default: 'venet0'
    add_index :vpses, :veth_name

    add_column :vpses, :veth_mac, :string, limit: 17, null: true
    add_index :vpses, :veth_mac, unique: true

    add_column :ip_addresses, :vps_id, :integer, null: true
    add_index :ip_addresses, :vps_id

    IpAddress.where.not(network_interface_id: nil).each do |ip|
      ip.update!(vps_id: ip.network_interface.vps_id)
    end

    Vps.where('object_state < 3').each do |vps|
      netif = NetworkInterface.where(vps_id: vps.id).order('id').take!

      vps.update!(
        veth_name: netif.name,
        veth_mac: netif.mac,
      )
    end

    remove_column :ip_addresses, :network_interface_id
    drop_table :network_interfaces
    drop_table :host_ip_addresses
  end
end
