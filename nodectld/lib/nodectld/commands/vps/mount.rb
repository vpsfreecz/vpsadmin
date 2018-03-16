module NodeCtld
  class Commands::Vps::Mount < Commands::Base
    handle 5302
    needs :system, :vps, :zfs, :pool

    def exec
      # TODO: we cannot add mounts at runtime
    end

    def rollback
      # TODO
    end
  end
end
