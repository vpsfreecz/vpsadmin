defmodule VpsAdmin.Transactional.Worker.Command.Server do
  use GenServer, restart: :transient

  require Logger
  alias VpsAdmin.Transactional.Distributor
  alias VpsAdmin.Base.NodeCtl

  ### Client interface
  def run({t, cmd}, func) do
    GenServer.start_link(__MODULE__, {{t, cmd}, func})
  end

  ### Server implementation
  @impl true
  def init({{t, cmd}, func}) do
    Logger.debug("Initializing executor of command #{t}:#{cmd.id}.#{func}")
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
    Logger.debug("Connected to nodectld")
    {:noreply, state}
  end

  def handle_info({:nodectl, msg}, state) do
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
