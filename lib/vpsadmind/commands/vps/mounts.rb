module VpsAdmind
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :vps, :zfs

    def exec
      syscmd("#{$CFG.get(:bin, :cp)} -p \"#{original_path(:mount)}\" \"#{backup_path(:mount)}\"")
      syscmd("#{$CFG.get(:bin, :cp)} -p \"#{original_path(:umount)}\" \"#{backup_path(:umount)}\"")

      action_script('mount')
      action_script('umount')
    end

    def rollback
      if File.exists?(backup_path(:mount))
        syscmd("#{$CFG.get(:bin, :cp)} -p \"#{backup_path(:mount)}\" \"#{original_path(:mount)}\"")
      end

      if File.exists?(backup_path(:umount))
        syscmd("#{$CFG.get(:bin, :cp)} -p \"#{backup_path(:umount)}\" \"#{original_path(:umount)}\"")
      end

      ok
    end

    protected
    def original_path(type)
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.#{type}"
    end

    def backup_path(type)
      "#{original_path(type)}.backup"
    end
  end
end
