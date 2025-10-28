module NodeCtld::RemoteCommands
  class Update < Base
    handle :update

    def exec
      case @command
      when 'ssh-host-keys'
        if @vps_ids&.any?
          NodeCtld::VpsSshHostKeys.update_vps_ids(@vps_ids)
        else
          NodeCtld::VpsSshHostKeys.update_all_vps
        end

      when 'os-release'
        if @vps_ids&.any?
          NodeCtld::VpsOsRelease.update_vps_ids(@vps_ids)
        else
          NodeCtld::VpsOsRelease.update_all_vps
        end

      else
        raise NodeCtld::SystemCommandFailed.new(nil, nil, "Unknown command #{@command}")
      end

      ok
    end
  end
end
