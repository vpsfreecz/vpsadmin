module VpsAdmind
  class Commands::Vps::OsTemplate < Commands::Base
    handle 2013

    def exec
      Vps.new(@vps_id).set_params({:ostemplate => @os_template})
    end

    def rollback
      Vps.new(@vps_id).set_params({:ostemplate => @original})
    end
  end
end
