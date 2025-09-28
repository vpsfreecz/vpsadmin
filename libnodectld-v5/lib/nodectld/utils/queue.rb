module NodeCtld::Utils
  module Queue
    def reserve_queue(name)
      queues = NodeCtld::Daemon.instance.instance_variable_get('@queues')
      self.step = "waiting for #{name} reservation"
      queues[name.to_sym].reserve(@command.chain_id, priority: @command.priority)
    end

    def release_queue(name)
      queues = NodeCtld::Daemon.instance.instance_variable_get('@queues')
      queues[name.to_sym].release(@command.chain_id)
    end
  end
end
