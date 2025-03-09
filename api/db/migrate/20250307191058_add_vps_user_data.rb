class AddVpsUserData < ActiveRecord::Migration[7.2]
  class OsTemplate < ActiveRecord::Base; end

  def change
    add_column :os_templates, :enable_script, :boolean, null: false, default: true
    add_column :os_templates, :enable_cloud_init, :boolean, null: false, default: true

    add_index :os_templates, :enable_script
    add_index :os_templates, :enable_cloud_init

    reversible do |dir|
      dir.up do
        OsTemplate.where(
          distribution: %w[nixos slackware]
        ).update_all(
          enable_script: false,
          enable_cloud_init: false
        )

        OsTemplate.where(
          distribution: %w[void]
        ).update_all(
          enable_cloud_init: false
        )
      end
    end

    create_table :vps_user_data do |t|
      t.references  :user,               null: false
      t.string      :label,              null: false, limit: 255
      t.integer     :format,             null: false, default: 0
      t.text        :content,            null: false
      t.timestamps
    end

    add_index :vps_user_data, :format
  end
end
