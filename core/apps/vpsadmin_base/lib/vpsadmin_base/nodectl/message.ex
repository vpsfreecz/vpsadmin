defmodule VpsAdmin.Base.NodeCtl.Message do
  defstruct [:type, :status, :response]

  def parse(msg), do: parse_type(msg)

  defp parse_type(%{"version" => v}) do
    {:ok, %__MODULE__{type: :init, response: %{version: v}}}
  end

  defp parse_type(msg), do: parse_status(msg)

  defp parse_status(%{"status" => "ok"} = msg), do: parse_response(msg, true)
  defp parse_status(%{"status" => "failed"} = msg), do: parse_response(msg, false)
  defp parse_status(_msg), do: invalid()

  defp parse_response(%{"response" => response}, status) do
    {:ok, %__MODULE__{type: :response, status: status, response: response}}
  end

  defp parse_response(_msg, _status), do: invalid()

  defp invalid, do: {:error, :invalid}
end
