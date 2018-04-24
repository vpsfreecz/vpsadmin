module NodeCtld::RemoteCommands
  class DelayedMount < Base
    handle :delayed_mount

    def exec
      mount = {}

      @mount.each do |k, v|
        mount[k.to_s] = v
      end

      NodeCtld::DelayedMounter.mount(@pool_fs, @vps_id.to_i, mount)
      ok
    end
  end
end
