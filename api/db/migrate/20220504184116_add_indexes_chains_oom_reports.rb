class AddIndexesChainsOomReports < ActiveRecord::Migration[6.1]
  def change
    add_index :transaction_chains, :created_at
    add_index :transaction_chains, %i(type state)
    add_index :oom_reports, :reported_at
  end
end
