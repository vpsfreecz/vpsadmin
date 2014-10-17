module VpsAdmind
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2002

    def exec
      Vps.new(@vps_id).passwd(@user, @password)
    end

    def post_save(db)
      db.prepared("UPDATE transactions SET t_param = '{}' WHERE t_id = ?", @command.id)
    end
  end
end
