module NodeCtld
  class Commands::Export::Set < Commands::Base
    handle 5407

    def exec
      s = NfsServer.new(@export_id, nil)
      s.set!(@new['threads'])
    end

    def rollback
      s = NfsServer.new(@export_id, nil)
      s.set!(@original['threads'])
    end
  end
end
