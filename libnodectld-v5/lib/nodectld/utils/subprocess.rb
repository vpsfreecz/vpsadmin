module NodeCtld
  # Contains helper methods to work with spawned subprocesses.
  module Utils::Subprocess
    # Fork and run the block in child process. The child process
    # is registered and watched by the vpsAdmind daemon.
    # No further transaction in the same chain will be executed
    # on *this* node until that subprocess finishes.
    # It has no effect on transactions on other nodes.
    def blocking_fork(&)
      child = Process.fork(&)
      Daemon.register_subprocess(@command.chain_id, child)
    end

    def killall_subprocesses
      @daemon.chain_blockers do |blockers|
        next unless blockers

        log('Killing all subprocesses')

        blockers.each_value do |pids|
          pids.each do |pid|
            log("Sending SIGTERM to subprocess #{pid}")
            Process.kill('TERM', pid)
          end
        end
      end
    end
  end
end
