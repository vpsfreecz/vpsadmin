module VpsAdmind::RemoteCommands
  class MountState < Base
    handle :mount_state

    def exec
      VpsAdmind::MountReporter.report(@vps_id.to_i, @mount_id.to_i, @state.to_sym)
      ok
    end
  end
end
