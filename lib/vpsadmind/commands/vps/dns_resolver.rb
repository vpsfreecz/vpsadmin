module VpsAdmind
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005

    def exec
      Vps.new(@vps_id).set_params({:nameserver => @nameserver})
    end
  end
end
