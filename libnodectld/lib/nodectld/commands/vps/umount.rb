module NodeCtld
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :osctl, :vps

    def exec
      return ok if status != :running

      mounter = Mounter.new(@pool_fs, @vps_id)
      @umounted_mounts = []

      @mounts.each do |m|
        DelayedMounter.unregister_vps_mount(@vps_id, m['id'])

        mounter.umount(m)
        @umounted_mounts << m
      end

      ok
    end

    def rollback
      mounts = @umounted_mounts || @mounts

      call_cmd(Commands::Vps::Mount, {
        pool_fs: @pool_fs,
        vps_id: @vps_id,
        mounts: mounts.reverse,
      })
    end
  end
end
