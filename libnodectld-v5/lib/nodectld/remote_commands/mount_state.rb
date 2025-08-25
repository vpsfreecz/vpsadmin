module NodeCtld::RemoteCommands
  class MountState < Base
    handle :mount_state

    def exec
      NodeCtld::MountReporter.report(@vps_id.to_i, @mount_id.to_i, @state.to_sym)
      ok
    end
  end
end
