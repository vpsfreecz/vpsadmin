defmodule VpsAdmin.Transactional.Worker.Distributed do
  use VpsAdmin.Transactional.Worker
  require Logger
  alias Transactional.Worker.Distributed.Monitor

  def run_command({t, cmd}, func) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for #{func}")
    {:ok, _pid} = Monitor.run_command({t, cmd}, func)
  end
end
