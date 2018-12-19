defmodule VpsAdmin.Transactional.Worker.Distributed do
  use VpsAdmin.Transactional.Worker
  require Logger
  alias Transactional.Worker.Distributed.Distributor

  def run_command({t, cmd}, :execute) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for execution")
    :ok = Distributor.run_command({t, cmd}, :execute)
  end

  defp run({t, cmd}, :rollback) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for rollback")
    :ok = Distributor.run_command({t, cmd}, :rollback)
  end
end
