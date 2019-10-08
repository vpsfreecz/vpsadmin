module TransactionChains
  class Export::EditHost < ::TransactionChain
    label 'Host*'

    # @param host [::Host]
    # @param opts [Hash]
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    def link_chain(host, opts)
      concerns(:affect, [host.export.class.name, host.export.id])

      new_host = ::ExportHost.find(host.id)
      new_host.assign_attributes(opts)

      append_t(Transactions::Export::DelHosts, args: [host.export, [host]])
      append_t(Transactions::Export::AddHosts, args: [host.export, [new_host]]) do |t|
        changes = Hash[new_host.changed.map { |attr| [attr, new_host.send(attr)] }]
        t.edit(host, changes)
      end

      host
    end
  end
end
