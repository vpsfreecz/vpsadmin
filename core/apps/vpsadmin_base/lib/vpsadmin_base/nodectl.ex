defmodule VpsAdmin.Base.NodeCtl do
  use GenServer
  import Kernel, except: [send: 2]
  require Logger
  alias VpsAdmin.Base.NodeCtl

  ### Client interface
  def start_link do
    GenServer.start_link(__MODULE__, self())
  end

  def send(nodectl, msg) do
    GenServer.cast(nodectl, {:send, msg})
  end

  def close(nodectl) do
    GenServer.call(nodectl, :close)
  end

  ### Server implementation
  @impl true
  def init(parent) do
    {:ok, socket} =
      :gen_tcp.connect(
        {:local, '/run/nodectl/nodectld.sock'},
        0,
        [:local, active: true, packet: :line]
      )

    {:ok, {parent, socket}}
  end

  @impl true
  def handle_info({:tcp, socket, raw_msg}, {parent, socket} = state) do
    case decode(raw_msg) do
      {:ok, msg} ->
        handle_msg(msg, parent)
      {:error, :invalid} ->
        Logger.info("Ignoring invalid message from nodectl: '#{inspect(raw_msg)}'")
    end

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :closed, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_cast({:send, msg}, {_parent, socket} = state) do
    :gen_tcp.send(socket, encode(msg))
    {:noreply, state}
  end

  @impl true
  def handle_call(:close, _from, {parent, socket}) do
    :gen_tcp.close(socket)
    {:reply, :ok, {parent, nil}}
  end

  defp handle_msg(%{type: :init}, _parent), do: :ok

  defp handle_msg(%{type: :response} = msg, parent) do
    Kernel.send(parent, {:nodectl, msg})
  end

  defp encode(msg) do
    Jason.encode!(msg) <> "\n"
  end

  defp decode(msg) do
    msg
    |> to_string()
    |> String.trim()
    |> Jason.decode!()
    |> NodeCtl.Message.parse()
  end
end
