module NodeCtld
  class Commands::Export::Destroy < Commands::Base
    handle 5402

    def exec
      s = NfsServer.new(@export_id, @address)
      s.destroy!
    end

    def rollback
      s = NfsServer.new(@export_id, @address)
      s.create!
    end
  end
end
