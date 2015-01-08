module VpsAdmind
  class Commands::Pool::Create < Commands::Base
    handle 5250

    include Utils::System
    include Utils::Zfs

    SPECIALS = [:mounts, :download]

    def exec
      zfs(:create, '-p', @pool_fs)
      zfs(:create, '-p', "#{@pool_fs}/vpsadmin")

      SPECIALS.each do |s|
        zfs(:create, '-p', "#{@pool_fs}/vpsadmin/#{s}")
      end
    end

    def rollback
      SPECIALS.each do |s|
        zfs(:destroy, nil, "#{@pool_fs}/vpsadmin/#{s}", [1])
      end

      zfs(:destroy, nil, "#{@pool_fs}/vpsadmin", [1])
      zfs(:destroy, nil, @pool_fs, [1])
    end
  end
end
