module Transactions::Vps
  class SendRootfs < ::Transaction
    t_name :vps_send_rootfs
    t_type 3031
    queue :zfs_send

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {}
    end
  end
end
