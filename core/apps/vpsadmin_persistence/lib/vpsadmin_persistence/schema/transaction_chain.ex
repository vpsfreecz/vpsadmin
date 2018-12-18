defmodule VpsAdmin.Persistence.Schema.TransactionChain do
  use VpsAdmin.Persistence.Schema

  defenum(
    State,
    Enum.with_index(~w(staged executing done rollingback failed aborted resolved)a)
  )

  defenum(ConcernType, Enum.with_index(~w(chain_affect chain_transform)a))

  schema "transaction_chains" do
    field(:name, :string)
    field(:type, :string)
    field(:state, State)
    field(:size, :integer)
    field(:progress, :integer)
    field(:user_id, :integer)
    field(:urgent_rollback, :boolean)
    field(:concern_type, ConcernType)
    field(:user_session_id, :integer)

    timestamps(
      type: :utc_datetime,
      inserted_at: :created_at,
      updated_at: :updated_at
    )

    has_many(:transactions, Schema.Transaction)
  end
end
