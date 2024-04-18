class AddMetricsAccessTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :metrics_access_tokens do |t|
      t.references  :token,               null: false
      t.references  :user,                null: false
      t.string      :metric_prefix,       null: false, limit: 30, default: 'vpsadmin_'
      t.integer     :use_count,           null: false, default: 0
      t.datetime    :last_use,            null: true
      t.timestamps                        null: false
    end
  end
end
