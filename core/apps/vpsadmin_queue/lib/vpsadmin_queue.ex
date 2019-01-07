defmodule VpsAdmin.Queue do
  @moduledoc """
  Named FIFO queue for executing commands.

  A queue must be first created, usually as a part of the supervision tree,
  using `start_link/1`. Commands are then enqueued using `enqueue/4`.

  The queue has a configured size, which determines the maximum number
  of commands that are executed simultaneously. Other commands wait in queue
  for an execution slot to open.
  """

  alias VpsAdmin.Queue

  @type name :: atom
  @type on_start :: {:ok, pid} | {:error, term}

  @spec start_link({name, integer} | {name, integer, integer}) :: GenServer.on_start()
  def start_link(arg) do
    Queue.Server.start_link(arg)
  end

  @spec enqueue(
          name,
          term,
          {atom, atom, list},
          GenServer.server(),
          keyword
        ) :: :ok
  @doc """
  Add command to the queue.

  The command is identified by `id`. It can be any term, but you have to ensure
  its uniqueness. `mfa` is a tuple `{module, function, arguments}`. This
  function is called to execute the command. It has to return type
  `VpsAdmin.Queue.on_start`. The process must not be linked to the queue, but
  should be a part of an independent supervision tree, so as to not bring down
  the queue when the executed process is killed.

  `parent` is a name of a process that is to be notified when the command
  is executed and when it finishes. Message `{:queue, id, :executing}` is sent
  when execution starts, message `{:queue, id, :done, exit_reason}` is sent
  when the executed process finishes with whatever reason. When the process
  cannot be started, message `{:queue, id, :error, error}` is sent.
  """
  def enqueue(queue, id, mfa, parent, opts \\ []) do
    Queue.Server.enqueue(queue, id, mfa, parent, opts)
  end

  @spec reserve(
          name,
          term,
          integer,
          GenServer.server()
        ) :: :ok | {:error, :invalid}
  @doc """
  Reserve one or more execution slots

  The reservation happens immediately if the requested execution slots are free.
  If they are not, the reservation request is enqueued and will take place as
  soon as previous runnable and reservation requests are fullfilled. Message
  `{:queue, name, :reserved}` is sent to `parent` once the reservation is
  secured.

  The queue size is shrunk until the reservation is released. Reserved slots
  can only be used by `enqueue/4` calls with appropriate `name` option.
  """
  def reserve(queue, name, size, parent, opts \\ []) do
    Queue.Server.reserve(queue, name, size, parent, opts)
  end

  @spec release(
          name,
          term,
          integer
        ) :: :ok | {:error, :invalid} | {:error, :notfound}
  @doc """
  Release previously reserved execution slots
  """
  def release(queue, name, size) do
    Queue.Server.release(queue, name, size)
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
