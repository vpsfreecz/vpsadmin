class AddStreamDownloads < ActiveRecord::Migration
  def change
    add_column :snapshot_downloads, :format, :integer, null: false, default: 0
    add_column :snapshot_downloads, :from_snapshot_id, :integer, null: true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute(
            "UPDATE `transaction_chains`
             SET type = 'TransactionChains::Dataset::FullDownload'
             WHERE type = 'TransactionChains::Dataset::Download'"
        )
      end
    end
  end
end
