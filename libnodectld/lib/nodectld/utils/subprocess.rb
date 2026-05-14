module NodeCtld
  # Contains helper methods to work with spawned subprocesses.
  module Utils::Subprocess
    # Fork and run the block in child process. The child process
    # is registered and watched by the vpsAdmind daemon.
    # No further transaction in the same chain will be executed
    # on *this* node until that subprocess finishes.
    # It has no effect on transactions on other nodes.
    def blocking_fork(&)
      child = Process.fork do
        Process.setpgrp
        yield
      end

      Daemon.register_subprocess(@command.chain_id, child)
    end

    def killall_subprocesses
      daemon = @daemon || Daemon.instance
      return unless daemon

      daemon.chain_blockers do |blockers|
        next unless blockers

        chain_id = @command&.chain_id
        selected = if chain_id
                     { chain_id => blockers[chain_id] || [] }
                   else
                     blockers
                   end

        selected.each do |selected_chain_id, pids|
          next if pids.empty?

          log("Killing subprocesses for chain #{selected_chain_id}")

          pids.each do |pid|
            log("Sending SIGTERM to subprocess group #{pid}")

            begin
              Process.kill('TERM', -pid)
            rescue Errno::ESRCH
              begin
                Process.kill('TERM', pid)
              rescue Errno::ESRCH
                nil
              end
            end
          end
        end
      end
    end
  end
end
