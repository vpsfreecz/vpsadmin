module NodeCtld
  class Commands::Export::Disable < Commands::Base
    handle 5404

    def exec
      s = NfsServer.new(@export_id, nil)
      s.stop!
    end

    def rollback
      s = NfsServer.new(@export_id, nil)
      s.start!
    end
  end
end
