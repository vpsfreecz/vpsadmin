module Transactions::Vps
  class ShaperRootChange < ::Transaction
    t_name :vps_shaper_root_change
    t_type 2012

    def params(node)
      self.t_vps = nil
      self.t_server = node.id

      ret = {
          max_tx: node.max_tx,
          max_rx: node.max_rx
      }

      if node.max_tx_changed? || node.max_rx_changed?
        ret[:original] = {
            max_tx: node.max_tx_was,
            max_rx: node.max_rx_was
        }
      end

      ret
    end
  end
end
