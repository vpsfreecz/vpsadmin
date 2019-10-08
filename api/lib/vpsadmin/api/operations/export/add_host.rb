require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::AddHost < Operations::Base
    # @param export [::Export]
    # @param opts [Hash]
    # @option opts [::IpAddress] :ip_address
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @return [TransactionChain, ExportHost]
    def run(export, opts)
      chain, hosts = TransactionChains::Export::AddHosts.fire(
        export,
        [::ExportHost.new(
          export: export,
          ip_address: opts[:ip_address],
          rw: with_default(export, opts, :rw),
          sync: with_default(export, opts, :sync),
          subtree_check: with_default(export, opts, :subtree_check),
          root_squash: with_default(export, opts, :root_squash),
        )]
      )
      return chain, hosts.first
    end

    protected
    def with_default(export, opts, k)
      opts[k].nil? ? export.send(k) : opts[k]
    end
  end
end
