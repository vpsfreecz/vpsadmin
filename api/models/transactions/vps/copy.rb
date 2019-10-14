module Transactions::Vps
  class Copy < ::Transaction
    t_name :vps_copy
    t_type 3040
    queue :vps

    # @param vps [::Vps]
    # @param as_id [Integer]
    # @param opts [Hash]
    # @option opts [Boolean] :consistent
    # @option opts [Boolean] :network_interfaces
    def params(vps, as_id, opts = {})
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        as_id: as_id.to_s,
        consistent: opts[:consistent].nil? ? true : opts[:consistent],
        network_interfaces: opts[:network_interfaces] || false,
      }
    end
  end
end
