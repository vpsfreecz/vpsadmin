module NodeCtld
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system

    def exec
      VpsConfig.create_or_replace(@vps_id) do |cfg|
        cfg.uuid = @uuid
        cfg.vm_type = @vm_type
        cfg.os = @os
        cfg.os_family = @os_family
        cfg.console_port = @console_port
        cfg.distribution = @distribution
        cfg.version = @version
        cfg.arch = @arch
        cfg.variant = @variant
        cfg.hostname = @hostname
        cfg.rootfs_label = @rootfs_label

        ConfigDrive.create(@vps_id, cfg)
      end

      syscmd("consolectl start #{@vps_id} #{@console_port}") if @console_port

      ok
    end

    def rollback
      call_cmd(Commands::Vps::Destroy, vps_id: @vps_id, uuid: @uuid)
      ok
    end
  end
end
