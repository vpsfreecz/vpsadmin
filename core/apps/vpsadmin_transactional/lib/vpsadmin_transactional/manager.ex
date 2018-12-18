defmodule VpsAdmin.Transactional.Manager do
  alias VpsAdmin.Transactional

  @callback open_transactions() ::
              [{Transactional.Transaction.t(), [Transactional.Command.t()]}]
              | {:error, term}
  @callback close_transaction(Transactional.Transaction.t()) :: any
  @callback abort_transaction(Transactional.Transaction.t()) :: any
  @callback command_started(Transactional.Transaction.t(), Transactional.Command.t()) :: any
  @callback command_finished(Transactional.Transaction.t(), Transactional.Command.t()) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour VpsAdmin.Transactional.Manager
      alias VpsAdmin.Transactional
    end
  end

  def add_transaction(t, manager, worker) do
    Transactional.Manager.Transaction.Supervisor.add_transaction(t, manager, worker)
  end
end
