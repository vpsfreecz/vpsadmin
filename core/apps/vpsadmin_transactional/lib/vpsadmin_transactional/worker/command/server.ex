defmodule VpsAdmin.Transactional.Worker.Command.Server do
  use GenServer, restart: :transient

  alias VpsAdmin.Transactional.Distributor
  alias VpsAdmin.Base.NodeCtl

  ### Client interface
  def run({t, cmd}, func) do
    GenServer.start_link(__MODULE__, {{t, cmd}, func})
  end

  ### Server implementation
  @impl true
  def init({{t, cmd}, func}) do
    IO.inspect("yo initializing cmd #{t}:#{cmd.id} executor for #{func}")
    {:ok, %{t: t, cmd: cmd, func: func}, {:continue, :startup}}
  end

  @impl true
  def handle_continue(:startup, state) do
    {:ok, nodectl} = NodeCtl.start_link()
    NodeCtl.send(
      nodectl,
      %{
        command: :execute,
        params: %{
          transaction_id: state.t,
          command_id: state.cmd.id,
          input: state.cmd.input,
          run: state.func
        }
      }
    )
    {:noreply, Map.put(state, :nodectl, nodectl)}
  end

  @impl true
  def handle_info({:nodectl, %{"version" => v}}, state) do
    IO.inspect("nodectld reports version '#{v}'")
    {:noreply, state}
  end

  def handle_info({:nodectl, msg}, state) do
    IO.inspect("reveived msg")
    IO.inspect(msg)

    NodeCtl.close(state.nodectl)

    Distributor.report_result(
      {
        state.t,
        %{state.cmd
          | status: if(msg.status, do: :done, else: :failed),
            output: msg.response}}
    )

    {:stop, :normal, Map.delete(state, :nodectl)}
  end
end
