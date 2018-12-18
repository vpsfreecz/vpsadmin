defmodule VpsAdmin.Transactional.Transaction do
  @type id :: term
  @type state :: :executing | :rollingback | :done | :failed | :rolledback | :aborted
  @type t :: %__MODULE__{
          id: id,
          state: state
        }
  defstruct ~w(id state)a

  def new(id, state), do: %__MODULE__{id: id, state: state}
end
