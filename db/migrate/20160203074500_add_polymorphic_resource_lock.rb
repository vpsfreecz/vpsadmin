class AddPolymorphicResourceLock < ActiveRecord::Migration
  def change
    add_reference :resource_locks, :locked_by, null: true, polymorphic: true, index: true
    remove_column :resource_locks, :transaction_chain_id, :integer, null: true
  end
end
