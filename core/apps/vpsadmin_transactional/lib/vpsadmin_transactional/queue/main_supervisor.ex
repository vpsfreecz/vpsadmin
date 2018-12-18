defmodule VpsAdmin.Transactional.Queue.MainSupervisor do
  @moduledoc false

  use Supervisor
  alias VpsAdmin.Transactional.Queue

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: Queue.Registry},
      Queue.QueueSupervisor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
