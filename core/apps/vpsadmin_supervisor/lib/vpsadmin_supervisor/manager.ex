defmodule VpsAdmin.Supervisor.Manager do
  use VpsAdmin.Transactional.Manager
  require Logger
  alias VpsAdmin.Persistence
  alias VpsAdmin.Supervisor.Convert

  @impl true
  def open_transactions do
    Persistence.Query.TransactionChain.get_open_ids()
  end

  @impl true
  def get_transaction(id) do
    id
    |> Persistence.Query.TransactionChain.get()
    |> Convert.DbToRuntime.chain_to_transaction()
  end

  @impl true
  def get_commands(id) do
    id
    |> Persistence.Query.Transaction.list()
    |> Enum.map(&Convert.DbToRuntime.transaction_to_command/1)
  end

  @impl true
  def close_transaction(trans) do
    Logger.debug("Closing transaction #{trans.id}")

    Persistence.Query.TransactionChain.close(
      trans.id,
      Convert.RuntimeToDb.chain_state(trans.state)
    )
  end

  @impl true
  def abort_transaction(trans) do
    Logger.debug("Aborting transaction #{trans.id}")
  end

  @impl true
  def command_started(trans, cmd) do
    Persistence.Query.Transaction.started(cmd.id)
  end

  @impl true
  def command_finished(trans, cmd) do
    Logger.debug("Persisting command state #{trans.id}:#{cmd.id} -> #{cmd.state}")

    {done, status, output} = Convert.RuntimeToDb.command_result(cmd)
    Persistence.Query.Transaction.finished(cmd.id, done, status, output)

    Persistence.Query.TransactionChain.progress(trans.id, done, status)
  end
end
