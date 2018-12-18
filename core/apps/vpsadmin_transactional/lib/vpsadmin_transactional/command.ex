defmodule VpsAdmin.Transactional.Command do
  @type t :: %__MODULE__{
          id: integer,
          node: atom,
          queue: atom,
          reversible: :reversible | :irreversible | :ignore,
          state: :queued | :executed | :rolledback,
          status: nil | :done | :failed,
          input: map,
          output: map
        }
  defstruct ~w(id node queue reversible state status input output)a
end
