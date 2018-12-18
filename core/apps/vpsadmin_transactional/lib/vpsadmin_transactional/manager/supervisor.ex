defmodule VpsAdmin.Transactional.Manager.Supervisor do
  use Supervisor

  alias VpsAdmin.Transactional.Manager

  def start_link(mod) do
    Supervisor.start_link(__MODULE__, mod)
  end

  @impl true
  def init(mod) do
    children = [
      {Registry, keys: :unique, name: Manager.Transaction.Registry},
      Manager.Transaction.Supervisor,
      {Manager.Transaction.Initializer, mod}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
