defmodule VpsAdmin.Transactional.Queue do
  @moduledoc """
  Named FIFO queue for executing commands.

  A queue must be first created, usually as a part of the supervision tree,
  using `start_link/1`. Commands are then enqueued using `enqueue/4`.

  The queue has a configured size, which determines the maximum number
  of commands that are executed simultaneously. Other commands wait in queue
  for an execution slot to open.
  """

  alias VpsAdmin.Transactional.Queue

  @type name :: atom

  @spec start_link({name, integer}) :: GenServer.on_start()
  def start_link({queue, size} = arg) do
    Queue.Server.start_link(arg)
  end

  @spec enqueue(name, term, {atom, atom, list}, GenServer.server()) :: :ok
  @doc """
  Add command to the queue.

  The command is identified by `id`. It can be any term, but you have to ensure
  its uniqueness. `mfa` is a tuple `{module, function, arguments}`. This
  function is called to execute the command. It has to return type
  `GenServer.on_start`. The process has to be started as linked.

  `parent` is a name of a process that is to be notified when the command
  is executed and when it finishes. Message `{:queue, id, :executing}` is sent
  when execution starts, message `{:queue, id, :done, exit_reason}` is sent
  when the executed process finishes with whatever reason. When the process
  cannot be started, message `{:queue, id, :error, error}` is sent.
  """
  def enqueue(queue, id, mfa, parent) do
    Queue.Server.enqueue(queue, id, mfa, parent)
  end

  @spec status(queue :: name) :: %{
          executing: integer,
          queued: integer,
          size: integer
        }
  def status(queue) do
    Queue.Server.status(queue)
  end
end
