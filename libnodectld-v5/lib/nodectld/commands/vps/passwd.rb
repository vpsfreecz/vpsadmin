module NodeCtld
  class Commands::Vps::Passwd < Commands::Base
    handle 2002
    needs :libvirt, :vps

    def exec
      vps.passwd(@user, @password)
      ok
    end

    def rollback
      ok
    end

    def on_save(db)
      db.prepared("UPDATE transactions SET input = '{}' WHERE id = ?", @command.id)
    end
  end
end
