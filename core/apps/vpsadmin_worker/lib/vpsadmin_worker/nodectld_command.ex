defmodule VpsAdmin.Worker.NodeCtldCommand do
  alias VpsAdmin.Worker

  def run_command({t, cmd}, func) do
    Worker.NodeCtldCommand.Supervisor.run_command({t, cmd}, func)
  end
end
