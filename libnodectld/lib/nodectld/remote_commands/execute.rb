module NodeCtld
  class RemoteCommands::Execute < RemoteCommands::Base
    handle :execute

    def exec
      cmd = Command.new(
        @transaction_id,
        @command_id,
        @input[:handle],
        @input[:input]
      )

      ok.merge(output: Worker.run(cmd, @run))

    rescue CommandFailed => e
      error.merge(output: e.error)
    end
  end
end
