module VpsAdmind
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005

    def exec
      Vps.new(@vps_id).set_params({:nameserver => @nameserver})
    end

    def rollback
      Vps.new(@vps_id).set_params({:nameserver => @original})
    end
  end
end
