module NodeCtld
  class Commands::Vps::ApplyUserData < Commands::Base
    handle 2036
    needs :libvirt, :vps

    def exec
      raise 'domain not active' unless domain.active?

      case @format
      when 'nixos_configuration', 'nixos_flake_configuration', 'nixos_flake_uri'
        distconfig!(domain, ['nixos-config-apply', @format], input: @content)
      else
        raise "Unable to apply #{@format.inspect}"
      end

      ok
    end

    def rollback
      ok
    end
  end
end
