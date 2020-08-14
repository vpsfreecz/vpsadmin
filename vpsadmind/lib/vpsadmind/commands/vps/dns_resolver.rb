module VpsAdmind
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005

    def exec
      Vps.new(@vps_id).set_params({:nameserver => @nameserver})
    end

    def rollback
      if @original
        Vps.new(@vps_id).set_params({:nameserver => @original})
      else
        syscmd("sed -r -i '/^NAMESERVER=\"[^\"]+\"$/d' #{ve_conf}")
      end
    end
  end
end
