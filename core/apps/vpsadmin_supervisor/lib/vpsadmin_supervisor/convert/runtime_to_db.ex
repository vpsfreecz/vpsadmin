defmodule VpsAdmin.Supervisor.Convert.RuntimeToDb do
  def chain_state(:rolledback), do: :failed
  def chain_state(v) when v in ~w(executing rollingback done failed aborted)a, do: v

  def command_state(:queued), do: :waiting
  def command_state(v) when v in ~w(executed rolledback)a, do: v

  def command_status(nil), do: :queued
  def command_status(v) when v in ~w(done failed)a, do: v

  def command_result(cmd) do
    {command_state(cmd.state), command_status(cmd.status), cmd.output}
  end
end
