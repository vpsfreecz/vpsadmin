defmodule VpsAdmin.Persistence.ReliableQuery do
  alias VpsAdmin.Persistence.ReliableQuery

  def run(func) do
    ReliableQuery.Supervisor.run(func)
  end
end
