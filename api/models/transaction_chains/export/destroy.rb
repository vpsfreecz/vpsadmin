module TransactionChains
  class Export::Destroy < ::TransactionChain
    label 'Destroy'

    # @param export [::Export]
    def link_chain(export, *args)
      concerns(:affect, [export.class.name, export.id])

      host_addr = export.host_ip_addresses.first

      lock(host_addr.ip_address)
      lock(export.network_interface)
      lock(export)

      append_t(Transactions::Export::Disable, args: [export]) do |t|
        t.edit(export, enabled: false)
      end

      append_t(Transactions::Export::Destroy, args: [export, host_addr]) do |t|
        t.edit(host_addr.ip_address, network_interface_id: nil)
        t.just_destroy(export.network_interface)
        export.export_hosts.each { |host| t.just_destroy(host) }
        t.destroy(export)
      end

      if export.snapshot_in_pool_clone
        use_chain(SnapshotInPool::FreeClone, args: export.snapshot_in_pool_clone)
      end
    end
  end
end
