module VpsAdmind
  class Commands::Vps::CreateRoot < Commands::Base
    handle 4002

    include Utils::System
    include Utils::Vz
    include Utils::Vps

    def exec
      syscmd("#{$CFG.get(:bin, :mkdir)} #{ve_root}")
    end
  end
end
