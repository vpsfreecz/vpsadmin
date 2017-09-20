module VpsAdmind
  class Commands::Vps::Destroy < Commands::Base
    handle 3002
    needs :system, :vz, :vps, :zfs

    def exec
      syscmd("#{$CFG.get(:bin, :rmdir)} #{ve_root}")

      Dir.glob("#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.{mount,umount,conf}").each do |cfg|
        syscmd("#{$CFG.get(:bin, :mv)} #{cfg} #{cfg}.destroyed")
      end

      mounts_path = File.join($CFG.get(:vpsadmin, :mounts_dir), "#{@vps_id}.mounts")

      if File.exists?(mounts_path)
        syscmd("#{$CFG.get(:bin, :mv)} #{mounts_path} #{mounts_path}.destroyed")
      end

      ok
    end
  end
end
