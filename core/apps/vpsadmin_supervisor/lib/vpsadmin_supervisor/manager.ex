defmodule VpsAdmin.Supervisor.Manager do
  use VpsAdmin.Transactional.Manager
  alias VpsAdmin.Persistence
  alias VpsAdmin.Supervisor.Convert

  @impl true
  def open_transactions do
    IO.inspect("yo my manager called bro")

    Persistence.Query.TransactionChain.get_open()
    |> Enum.map(&Convert.DbToRuntime.chain_to_transaction/1)
  end

  @impl true
  def close_transaction(trans) do
    IO.inspect("would persist close #{trans.id}")

    Persistence.Query.TransactionChain.close(
      trans.id,
      Convert.RuntimeToDb.chain_state(trans.state)
    )
  end

  @impl true
  def abort_transaction(trans) do
    IO.inspect("would persist abort #{trans.id}")
  end

  @impl true
  def command_started(trans, cmd) do
    Persistence.Query.Transaction.started(cmd.id)
  end

  @impl true
  def command_finished(trans, cmd) do
    IO.inspect("would persist update #{trans.id}:#{cmd.id} -> #{cmd.state}")

    {done, status, output} = Convert.RuntimeToDb.command_result(cmd)
    Persistence.Query.Transaction.finished(cmd.id, done, status, output)

    Persistence.Query.TransactionChain.progress(trans.id, done, status)
  end
end
