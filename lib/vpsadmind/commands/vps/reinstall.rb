module VpsAdmind
  class Commands::Vps::Reinstall < Commands::Base
    handle 3003

    def exec
      Vps.new(@vps_id).reinstall(@template, @hostname, @nameserver)

      ok
    end
  end
end
