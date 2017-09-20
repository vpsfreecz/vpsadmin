module VpsAdmind
  class Commands::Vps::UnmanageHostname < Commands::Base
    handle 2016
    needs :system, :vps

    def exec
      syscmd("sed -r -i '/^HOSTNAME=\"[^\"]+\"$/d' #{ve_conf}")
    end

    def rollback
      Vps.new(@vps_id).set_params({:hostname => @hostname})
    end
  end
end
