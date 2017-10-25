defmodule VpsAdmin.Transactional.Queue.Supervisor do
  @moduledoc "Supervisor for execution queues"

  use Supervisor

  alias VpsAdmin.Transactional.Queue

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    Supervisor.init([
      {Queue, {:default, 4}},
    ], strategy: :one_for_one)
  end
end
