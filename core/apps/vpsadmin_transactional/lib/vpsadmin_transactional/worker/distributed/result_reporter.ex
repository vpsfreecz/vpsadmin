defmodule VpsAdmin.Transactional.Worker.Distributed.ResultReporter do
  alias VpsAdmin.Transactional.Worker.Distributed.Distributor
  alias VpsAdmin.Transactional.Worker.Distributed.ResultReporter

  def report({t, cmd}) do
    ret =
      try do
        Distributor.report_result({t, cmd})
        :ok
      catch
        :exit, {{:nodedown, _}, _} -> :error
        :exit, {:noproc, _} -> :error
      end

    if ret == :error do
      {:ok, _pid} = ResultReporter.Supervisor.report({t, cmd})
    end

    :ok
  end
end
