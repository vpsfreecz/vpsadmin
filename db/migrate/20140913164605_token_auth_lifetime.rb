class TokenAuthLifetime < ActiveRecord::Migration
  class ApiToken < ActiveRecord::Base
  end

  def change
    add_column :api_tokens, :lifetime, :integer, null: false
    add_column :api_tokens, :interval, :integer

    reversible do |dir|
      dir.up do
        ApiToken.update_all(lifetime: 0)
      end
    end
  end
end
