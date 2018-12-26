defmodule VpsAdmin.Queue.QueueSupervisor do
  @moduledoc false

  use Supervisor
  alias VpsAdmin.Queue

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children =
      :vpsadmin_queue
      |> Application.get_env(:queues)
      |> Enum.map(&{Queue.Server, &1})

    Supervisor.init(children, strategy: :one_for_one)
  end
end
