class AddAuthenticationGeneration < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :authentication_generation, :integer,
               null: false,
               default: 0
  end
end
