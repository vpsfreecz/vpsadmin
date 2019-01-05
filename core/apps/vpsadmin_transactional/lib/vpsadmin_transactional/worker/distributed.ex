defmodule VpsAdmin.Transactional.Worker.Distributed do
  use VpsAdmin.Transactional.Worker
  require Logger
  alias Transactional.Worker.Distributed.Distributor

  def run_command({t, cmd}, func) do
    Logger.debug("Scheduling command #{t}:#{cmd.id} for #{func}")

    try do
      {:ok, _pid} = Distributor.run_command({t, cmd}, func)

    catch
      :exit, {{:nodedown, _}, _} ->
        {:unavailable, 30_000}
    end
  end
end
