defmodule VpsAdmin.Worker.CommandHandler do
  alias VpsAdmin.Queue
  alias VpsAdmin.Transactional.Command
  alias VpsAdmin.Worker.NodeCtldCommand

  # Queue slot reservation
  def run({t, %Command{input: %{handle: 101}} = cmd}, :execute) do
    :ok = Queue.reserve(
      cmd.queue,
      {:transaction, t},
      1,
      self(),
      urgent: cmd.input.urgent,
      priority: cmd.input.priority
    )
    {:ok, {t, cmd}}
  end

  def run({t, %Command{input: %{handle: 101}} = cmd}, :rollback) do
    Queue.release(cmd.queue, {:transaction, t}, 1)
    {:done, {t, %{cmd | status: :done}}}
  end

  # Queue slot release
  def run({t, %Command{input: %{handle: 102}} = cmd}, :execute) do
    Queue.release(cmd.queue, {:transaction, t}, 1)
    {:done, {t, %{cmd | status: :done}}}
  end

  def run({t, %Command{input: %{handle: 102}} = cmd}, :rollback) do
    new_cmd = %{cmd | status: :done}
    {:done, {t, new_cmd}}
  end

  # nodectld commands
  def run({t, cmd}, func) do
    :ok =
      Queue.enqueue(
        cmd.queue,
        {t, cmd},
        {NodeCtldCommand, :run_command, [{t, cmd}, func]},
        self(),
        name: {:transaction, t},
        urgent: cmd.input.urgent,
        priority: cmd.input.priority
      )

    {:ok, {t, cmd}}
  end
end
