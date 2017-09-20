module VpsAdmind
  class Commands::Queue::Reserve < Commands::Base
    handle 101
    needs :queue

    def exec
      reserve_queue(@queue)
      ok
    end

    def rollback
      release_queue(@queue)
      ok
    end
  end
end
