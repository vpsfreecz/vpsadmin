defmodule VpsAdmin.Transactional.Workers.Distributed do
  use VpsAdmin.Transactional.Worker
  alias Transactional.Distributor

  def run_command({t, cmd}, :execute) do
    IO.inspect("scheduling command #{t}:#{cmd.id} for execution")
    :ok = Distributor.run_command({t, cmd}, :execute)
  end

  defp run({t, cmd}, :rollback) do
    IO.inspect("scheduling command #{t}:#{cmd.id} for rollback")
    :ok = Distributor.run_command({t, cmd}, :rollback)
  end
end
