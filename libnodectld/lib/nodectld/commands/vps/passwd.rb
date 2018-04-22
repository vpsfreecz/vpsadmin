module NodeCtld
  class Commands::Vps::Passwd < Commands::Base
    handle 2002

    def exec
      Vps.new(@vps_id).passwd(@user, @password)
      ok
    end

    def rollback
      ok
    end

    def post_save(db)
      db.prepared("UPDATE transactions SET input = '{}' WHERE id = ?", @command.id)
    end
  end
end
