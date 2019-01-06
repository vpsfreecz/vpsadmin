defmodule VpsAdmin.Transactional.Worker.Distributed.Monitor do
  alias VpsAdmin.Transactional.Worker.Distributed.Monitor

  def run_command({t, cmd}, func) do
    {:ok, _pid} = Monitor.Supervisor.run_command({t, cmd}, func)
  end

  def report_result({_t, _cmd} = arg) do
    Monitor.Server.report_result(arg)
  end
end
