defmodule VpsAdmin.Transactional.Worker.Distributed do
  use VpsAdmin.Transactional.Worker
  require Logger
  alias Transactional.Worker.Distributed.Distributor

  def run_command({t, cmd}, :execute) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for execution")
    {:ok, _pid} = Distributor.run_command({t, cmd}, :execute)
  end

  def run_command({t, cmd}, :rollback) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for rollback")
    {:ok, _pid} = Distributor.run_command({t, cmd}, :rollback)
  end
end
