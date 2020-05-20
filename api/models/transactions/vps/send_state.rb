module Transactions::Vps
  class SendState < ::Transaction
    t_name :vps_send_state
    t_type 3033
    queue :zfs_send

    # @param vps [::Vps]
    # @param opts [Hash]
    # @option opts [Boolean] :clone
    # @option opts [Boolean] :start
    # @option opts [Boolean] :restart
    # @option opts [Boolean] :consistent
    def params(vps, opts = {})
      self.vps_id = vps.id
      self.node_id = vps.node_id

      opts
    end
  end
end
