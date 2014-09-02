module Transactions::Vps
  class ShaperRootChange < ::Transaction
    t_name :vps_shaper_root_change
    t_type 2012

    def params(node)
      self.t_vps = nil
      self.t_server = node.id

      {
          max_tx: node.max_tx,
          max_rx: node.max_rx
      }
    end
  end
end
