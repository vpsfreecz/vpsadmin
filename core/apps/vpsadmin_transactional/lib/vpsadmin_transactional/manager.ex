defmodule VpsAdmin.Transactional.Manager do
  alias VpsAdmin.Transactional.{Manager, Transaction, Command}

  @callback open_transactions() :: [Transaction.id()] | {:error, term}
  @callback get_transaction(Transaction.id()) :: Transaction.t() | {:error, term}
  @callback get_commands(Transaction.id()) :: [Command.t()] | {:error, term}
  @callback close_transaction(Transaction.t()) :: any
  @callback abort_transaction(Transaction.t()) :: any
  @callback command_started(Transaction.t(), Command.t()) :: any
  @callback command_finished(Transaction.t(), Command.t()) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour VpsAdmin.Transactional.Manager
      alias VpsAdmin.Transactional
    end
  end

  def add_transaction(t_id, manager, worker) do
    Manager.Transaction.Supervisor.add_transaction(t_id, manager, worker)
  end

  def report_result({t, cmd}) do
    Manager.Transaction.Server.report_result({t, cmd})
  end
end
