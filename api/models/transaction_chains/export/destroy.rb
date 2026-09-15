module TransactionChains
  class Export::Destroy < ::TransactionChain
    label 'Destroy'

    # @param export [::Export]
    def link_chain(export, *_args)
      concerns(:affect, [export.class.name, export.id])

      netif = export.network_interface
      host_addr = export.host_ip_addresses.first!
      host_addr.lock_with_ip!(self)
      lock(netif)
      netif.reload(lock: true)
      lock(export)
      export.reload(lock: true)
      unless netif.export_id == export.id && export.network_interface.id == netif.id &&
             host_addr.ip_address.network_interface_id == netif.id
        raise ResourceLocked.new(export, 'Export address assignment changed; retry the operation')
      end

      hosts = export.export_hosts.order(:ip_address_id).lock.to_a
      hosts.each { |host| host.lock_ip!(self) }

      export.update!(confirmed: ::Export.confirmed(:confirm_destroy))

      append_t(Transactions::Export::Disable, args: [export]) do |t|
        t.edit(export, enabled: false)
      end

      append_t(Transactions::Export::Destroy, args: [export, host_addr]) do |t|
        t.edit(host_addr.ip_address, network_interface_id: nil)
        t.just_destroy(netif)
        hosts.each { |host| t.just_destroy(host) }
        export.export_mounts.each { |ex_mnt| t.just_destroy(ex_mnt) }
        t.destroy(export)
      end

      return unless export.snapshot_in_pool_clone

      use_chain(SnapshotInPool::FreeClone, args: export.snapshot_in_pool_clone)
    end
  end
end
