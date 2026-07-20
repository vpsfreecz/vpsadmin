class WidenAuthTokenOpts < ActiveRecord::Migration[8.1]
  def change
    reversible do |dir|
      dir.up do
        change_column :auth_tokens, :opts, :text, limit: 65_535, null: true
      end

      dir.down do
        change_column :auth_tokens, :opts, :string, limit: 255, null: true
      end
    end
  end
end
