module NodeCtld
  class Commands::Vps::Mount < Commands::Base
    handle 5302
    needs :system, :osctl, :vps

    def exec
      return ok if status != :running

      mounter = Mounter.new(@pool_fs, @vps_id)

      @mounts.each do |mnt|
        DelayedMounter.unregister_vps_mount(@vps_id, mnt['id'])
        mounter.mount_after_start(mnt, true)
      end

      ok
    end

    def rollback
      call_cmd(Commands::Vps::Umount, {
        pool_fs: @pool_fs,
        mounts: @mounts.reverse,
        vps_id: @vps_id
      })
    end
  end
end
