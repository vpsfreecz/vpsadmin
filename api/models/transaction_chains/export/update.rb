module TransactionChains
  class Export::Update < ::TransactionChain
    label 'Update'

    # @param export [::Export]
    # @param opts [Hash]
    # @option opts [Boolean] :all_vps
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @option opts [Boolean] :enabled
    def link_chain(export, opts = {})
      concerns(:affect, [export.class.name, export.id])
      lock(export)

      new_export = ::Export.find(export.id)
      new_export.assign_attributes(opts)

      db_changes = {}
      toggle = nil

      new_export.changed.each do |attr|
        case attr
        when 'all_vps', 'rw', 'sync', 'subtree_check', 'root_squash'
          db_changes[attr] = new_export.send(attr)
        when 'enabled'
          toggle = new_export.enabled
        end
      end

      if toggle === false
        append_t(Transactions::Export::Disable, args: [new_export]) do |t|
          t.edit(export, enabled: new_export.enabled)
        end
      end

      if db_changes.any?
        export.export_hosts.each do |host|
          append_t(Transactions::Export::DelHosts, args: [export, [host.ip_address]])
          append_t(Transactions::Export::AddHosts, args: [new_export, [host.ip_address]])
        end

        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.edit(export, db_changes)
        end
      end

      if toggle === true
        append_t(Transactions::Export::Enable, args: [new_export]) do |t|
          t.edit(export, enabled: new_export.enabled)
        end
      end

      export
    end
  end
end
