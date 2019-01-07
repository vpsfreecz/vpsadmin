defmodule VpsAdmin.Worker.Executor do
  alias VpsAdmin.Worker.Executor

  def report_result({_t, _cmd} = arg) do
    Executor.Server.report_result(arg)
  end

  def retrieve_result({_t, _cmd} = command, func) do
    Executor.Server.retrieve_result(command, func)
  end
end
