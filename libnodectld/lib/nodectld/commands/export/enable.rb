module NodeCtld
  class Commands::Export::Enable < Commands::Base
    handle 5403

    def exec
      s = NfsServer.new(@export_id, nil)
      s.start!
    end

    def rollback
      s = NfsServer.new(@export_id, nil)
      s.stop!
    end
  end
end
