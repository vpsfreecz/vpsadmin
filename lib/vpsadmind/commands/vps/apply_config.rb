module VpsAdmind
  class Commands::Vps::ApplyConfig < Commands::Base
    handle 2008
    needs :system, :vz

    def exec
      n = Node.new

      syscmd("#{$CFG.get(:bin, :cp)} -p \"#{cfg_path}\" \"#{cfg_backup_path}\"")

      @configs.each do |cfg|
        vzctl(:set, @vps_id, {:applyconfig => cfg, :setmode => 'restart'}, true)

        path = n.conf_path("original-#{cfg}")

        if File.exists?(path)
          content = File.new(path).read

          m = nil
          quota = nil

          if (m = content.match(/^DISKSPACE\=\"\d+\:(\d+)\"/))
            quota = m[1].to_i * 1024 # vzctl saves diskspace in kB

          elsif (m = content.match(/^DISKSPACE\=\"\d+[GMK]\:(\d+[GMK])\"/))
            quota = m[1]
          end

          if quota
            zfs(:set, "refquota=#{quota}", ve_private_ds)
          end
        end
      end
      ok
    end

    def rollback
      if File.exists?(cfg_backup_path)
        syscmd("#{$CFG.get(:bin, :cp)} -p \"#{cfg_backup_path}\" \"#{cfg_path}\"")
      end

      ok
    end

    protected
    def cfg_path
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.conf"
    end

    def cfg_backup_path
      "#{cfg_path}.backup"
    end
  end
end
