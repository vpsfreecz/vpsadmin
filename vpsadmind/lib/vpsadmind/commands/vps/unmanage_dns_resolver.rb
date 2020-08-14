module VpsAdmind
  class Commands::Vps::UnmanageDnsResolver < Commands::Base
    handle 2027
    needs :system, :vps

    def exec
      syscmd("sed -r -i '/^NAMESERVER=\"[^\"]+\"$/d' #{ve_conf}")
    end

    def rollback
      Vps.new(@vps_id).set_params({nameserver: @original})
    end
  end
end
