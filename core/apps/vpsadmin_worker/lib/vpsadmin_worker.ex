defmodule VpsAdmin.Worker do
  use VpsAdmin.Transactional.Worker
  require Logger
  alias VpsAdmin.Worker.Monitor

  def run_command({t, cmd}, func) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for #{func}")
    {:ok, _pid} = Monitor.run_command({t, cmd}, func)
  end
end
