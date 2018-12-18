defmodule VpsAdmin.Persistence.Schema.Transaction do
  use VpsAdmin.Persistence.Schema

  defenum(Done, Enum.with_index(~w(waiting executed rolledback)a))
  defenum(Status, Enum.with_index(~w(failed done warning)a))
  defenum(Reversible, Enum.with_index(~w(irreversible reversible ignore)a))

  schema "transactions" do
    field(:user_id, :integer)
    field(:vps_id, :integer)
    field(:handle, :integer)
    field(:urgent, :integer)
    field(:priority, :integer)
    field(:done, Done)
    field(:status, Status)
    field(:input, :map)
    field(:output, :map)
    field(:reversible, Reversible)
    field(:started_at, :utc_datetime)
    field(:finished_at, :utc_datetime)
    field(:queue, :string)

    timestamps(
      type: :utc_datetime,
      inserted_at: :created_at,
      updated_at: false
    )

    belongs_to(:transaction_chain, Schema.TransactionChain)
    belongs_to(:depends_on, Schema.Transaction)
    belongs_to(:node, Schema.Node)
    has_many(:transaction_confirmations, Schema.TransactionConfirmation)
  end
end
