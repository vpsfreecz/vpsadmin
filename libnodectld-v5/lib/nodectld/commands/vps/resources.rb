module NodeCtld
  class Commands::Vps::Resources < Commands::Base
    handle 2003
    needs :system, :osctl

    def exec
      set('value')
      ok
    end

    def rollback
      set('original')
      ok
    end

    protected

    def set(key)
      # TODO
    end
  end
end
