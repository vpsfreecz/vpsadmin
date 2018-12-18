defmodule VpsAdmin.Transactional.Queue.QueueSupervisor do
  @moduledoc false

  use Supervisor
  alias VpsAdmin.Transactional.Queue

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children =
      :vpsadmin_transactional
      |> Application.get_env(:queues)
      |> Enum.map(fn v -> {Queue.Server, v} end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
