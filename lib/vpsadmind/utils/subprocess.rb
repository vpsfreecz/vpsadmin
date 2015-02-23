module VpsAdmind
  # Contains helper methods to work with spawned subprocesses.
  module Utils::Subprocess
    # Fork and run the block in child process. The child process
    # is registered and watched by the vpsAdmind daemon.
    # No further transaction in the same chain will be executed
    # on *this* node until that subprocess finishes.
    # It has no effect on transactions on other nodes.
    def blocking_fork(&block)
      child = Process.fork(&block)
      Daemon.register_subprocess(@command.chain_id, child)
    end
  end
end
