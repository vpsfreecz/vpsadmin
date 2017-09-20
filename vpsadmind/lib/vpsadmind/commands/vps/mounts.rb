module VpsAdmind
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :vps, :zfs, :pool

    def exec
      @mounts.each { |m| DelayedMounter.change_mount(@vps_id, m) }

      files.each do |path|
        next unless File.exists?(path)
        
        syscmd("#{$CFG.get(:bin, :cp)} -p \"#{path}\" \"#{backup_path(path)}\"")
        File.unlink(path)
      end

      action_script('mount')
      action_script('umount')

      File.open("#{mounts_path}.new", 'w') do |f|
        f.puts("MOUNTS = #{PP.pp(@mounts, '').strip}")
      end

      File.rename("#{mounts_path}.new", mounts_path)
      File.rename("#{original_path(:mount)}.new", original_path(:mount))
      File.rename("#{original_path(:umount)}.new", original_path(:umount))

      ok
    end

    def rollback
      files.reverse.each do |path|
        next unless File.exists?(backup_path(path))

        File.rename(backup_path(path), path)
      end

      ok
    end

    protected
    def files
      [
          original_path(:mount),
          original_path(:umount),
          mounts_path
      ]
    end

    def original_path(type)
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.#{type}"
    end

    def backup_path(path)
      "#{path}.backup"
    end

    def mounts_path
      File.join($CFG.get(:vpsadmin, :mounts_dir), "#{@vps_id}.mounts")
    end
  end
end
