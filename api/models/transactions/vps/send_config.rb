module Transactions::Vps
  class SendConfig < ::Transaction
    t_name :vps_send_config
    t_type 3030
    queue :vps

    # @param vps [::Vps]
    # @param node [::Node]
    # @param opts [Hash]
    # @option opts [Integer] :as_id
    # @option opts [Boolean] :network_interfaces
    # @option opts [Boolean] :snapshots
    # @option opts [String] :passphrase
    # @option opts [String] :from_snapshot
    # @option opts [Boolean] :preexisting_datasets
    def params(vps, node, opts = {})
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        node: node.ip_addr,
        as_id: (opts[:as_id] || vps.id).to_s,
        network_interfaces: opts[:network_interfaces] || false,
        snapshots: opts.has_key?(:snapshots) ? opts[:snapshots] : true,
        passphrase: opts[:passphrase],
        from_snapshot: opts[:from_snapshot],
        preexisting_datasets: opts[:preexisting_datasets],
      }
    end
  end
end
