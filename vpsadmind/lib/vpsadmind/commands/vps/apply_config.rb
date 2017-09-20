module VpsAdmind
  class Commands::Vps::ApplyConfig < Commands::Base
    handle 2008
    needs :system, :vz, :zfs

    def exec
      syscmd("#{$CFG.get(:bin, :cp)} -p \"#{cfg_path}\" \"#{cfg_backup_path}\"")

      @configs.each do |cfg|
        vzctl(:set, @vps_id, {:applyconfig => cfg, :setmode => 'restart'}, true)
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
