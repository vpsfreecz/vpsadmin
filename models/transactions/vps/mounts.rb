module Transactions::Vps
  class Mounts < ::Transaction
    t_name :vps_mounts
    t_type 5301

    def params(vps, cmds)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      mounts = []

      vps.vps_mounts.all.each do |m|
        if m.storage_export_id
          src = "#{m.storage_export.storage_root.node.addr}:#{m.storage_export.storage_root.root_path}/#{m.storage_export.path}"

        elsif !m.server_id.nil? && m.server_id != 0
          src = "#{m.node.addr}:#{m.src}"

        else
          src = m.src
        end

        mounts << {
            src: src,
            dst: m.dst,
            mount_opts: m.mount_opts,
            umount_opts: m.umount_opts,
            mode: m.mode
        }

        if cmds
          mounts.last.update({
              premount: m.cmd_premount,
              postmount: m.cmd_postmount,
              preumount: m.cmd_preumount,
              postumount: m.cmd_postumount
          })
        end
      end

      {
          mounts: mounts
      }
    end
  end
end
