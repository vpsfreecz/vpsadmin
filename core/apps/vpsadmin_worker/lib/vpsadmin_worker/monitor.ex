defmodule VpsAdmin.Worker.Monitor do
  alias VpsAdmin.Worker.Monitor

  def run_command({t, cmd}, func) do
    case Monitor.Supervisor.run_command({t, cmd}, func) do
      {:ok, _pid} = v ->
        v

      {:error, {:already_started, pid}} ->
        {:ok, pid}
    end
  end

  def report_result({_t, _cmd} = arg) do
    Monitor.Server.report_result(arg)
  end
end
