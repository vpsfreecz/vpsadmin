module NodeCtld
  class Commands::Queue::Release < Commands::Base
    handle 102
    needs :queue

    def exec
      release_queue(@queue)
      ok
    end

    def rollback
      ok
    end
  end
end
