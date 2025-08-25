module NodeCtld
  class Commands::Export::Create < Commands::Base
    handle 5401

    def exec
      s = NfsServer.new(@export_id, @address)
      s.create!(threads: @threads)
    end

    def rollback
      s = NfsServer.new(@export_id, @address)
      s.destroy
    end
  end
end
