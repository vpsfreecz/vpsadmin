defmodule VpsAdmin.Transactional.Worker.Distributed.Executor do
  alias VpsAdmin.Transactional.Worker.Distributed.Executor

  def report_result({_t, _cmd} = arg) do
    Executor.Server.report_result(arg)
  end

  def retrieve_result({_t, _cmd} = arg) do
    Executor.Server.retrieve_result(arg)
  end
end
