module VpsAdmind
  class Commands::Vps::Mounts < Commands::Base
    handle 5301

    include Utils::System
    include Utils::Zfs
    include Utils::Vps

    def exec
      action_script('mount')
      action_script('umount')
    end
  end
end
