defmodule VpsAdmin.Supervisor.Manager do
  use VpsAdmin.Transactional.Manager
  require Logger
  alias VpsAdmin.Persistence.Query
  alias VpsAdmin.Supervisor.Convert
  alias VpsAdmin.Transactional.Command

  @impl true
  def open_transactions do
    Query.TransactionChain.get_open_ids()
  end

  @impl true
  def get_transaction(id) do
    id
    |> Query.TransactionChain.get()
    |> Convert.DbToRuntime.chain_to_transaction()
  end

  @impl true
  def get_commands(id) do
    id
    |> Query.Transaction.list()
    |> Enum.map(&Convert.DbToRuntime.transaction_to_command/1)
  end

  @impl true
  def close_transaction(trans) do
    Logger.debug("Closing transaction #{trans.id}")

    Query.TransactionChain.close(
      trans.id,
      Convert.RuntimeToDb.chain_state(trans.state)
    )
  end

  @impl true
  def abort_transaction(trans) do
    Logger.debug("Aborting transaction #{trans.id}")

    Query.TransactionChain.abort(trans.id)
  end

  @impl true
  def command_started(_trans, cmd) do
    Query.Transaction.started(cmd.id)
  end

  @impl true
  def command_finished(trans, cmd) do
    Logger.debug("Persisting command state #{trans.id}:#{cmd.id} -> #{cmd.state}")

    {done, status, output} = Convert.RuntimeToDb.command_result(cmd)
    Query.Transaction.finished(cmd.id, done, status, output)

    Query.TransactionChain.progress(trans.id, done, status)

    if cmd.state == :executed && cmd.status == :done do
      post_save(cmd)
    end
  end

  # Clear input for Node.DeploySSHKey and Vps.Passwd
  defp post_save(%Command{input: %{handle: h}} = cmd) when h in [7, 2002] do
    Query.Transaction.clear_input(cmd.id)
  end

  # Dataset.DownloadSnapshot
  defp post_save(%Command{input: %{handle: 5004}} = cmd) do
    Query.Transaction.PostSave.snapshot_download(
      cmd.input.input["download_id"],
      cmd.output["size"],
      cmd.output["sha256sum"]
    )
  end

  # Dataset.GroupSnapshot
  defp post_save(%Command{input: %{handle: 5215}} = cmd) do
    {:ok, created_at, _} = DateTime.from_iso8601(cmd.output["created_at"])

    Query.Transaction.PostSave.group_snapshot(
      Enum.map(cmd.input.input["snapshots"], &(&1["snapshot_id"])),
      cmd.output["name"],
      created_at
    )
  end

  # Dataset.Snapshot
  defp post_save(%Command{input: %{handle: 5204}} = cmd) do
    {:ok, created_at, _} = DateTime.from_iso8601(cmd.output["created_at"])

    Query.Transaction.PostSave.snapshot(
      cmd.input.input["snapshot_id"],
      cmd.output["name"],
      created_at
    )
  end

  defp post_save(_cmd), do: nil
end
