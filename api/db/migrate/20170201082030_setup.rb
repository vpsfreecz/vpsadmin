class Setup < ActiveRecord::Migration
  def change
    create_table :news_logs do |t|
      t.text     :message,      null: false
      t.datetime :published_at, null: false
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        if ENV['FROM_VPSADMIN1'] && table_exists?(:log)
          ActiveRecord::Base.connection.execute(
              "INSERT INTO news_logs (message, published_at, created_at)
              SELECT msg, FROM_UNIXTIME(`timestamp`), FROM_UNIXTIME(`timestamp`)
              FROM log
              ORDER BY `timestamp`"
          )
        end
      end
    end
  end
end
