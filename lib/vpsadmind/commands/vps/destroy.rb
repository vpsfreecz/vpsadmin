module VpsAdmind
  class Commands::Vps::Destroy < Commands::Base
    handle 3002

    include Utils::System
    include Utils::Vz
    include Utils::Vps
    include Utils::Zfs

    def exec
      syscmd("#{$CFG.get(:bin, :rmdir)} #{ve_root}")

      Dir.glob("#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.{mount,umount,conf}").each do |cfg|
        syscmd("#{$CFG.get(:bin, :mv)} #{cfg} #{cfg}.destroyed")
      end

      ok
    end
  end
end
