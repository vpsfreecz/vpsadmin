module VpsAdmind::RemoteCommands
  class Set < Base
    handle :set

    def exec
      case @resource
        when 'config'
          @config.each do |change|
            $CFG.patch(change)
          end

          ok

        else
          raise SystemCommandFailed.new(nil, nil, "Unknown resource #{@resource}")
      end
    end
  end
end
