class Setup < ActiveRecord::Migration
  def change
    create_table :help_boxes do |t|
      t.string     :page,      null: false
      t.string     :action,    null: false
      t.references :language,  null: true
      t.text       :content,   null: false
      t.integer    :order,     null: false, default: 0
    end

    add_index :help_boxes, :page
    add_index :help_boxes, :action
    add_index :help_boxes, [:page, :action]

    reversible do |dir|
      dir.up do
        if ENV['FROM_VPSADMIN1'] && table_exists?(:helpbox)
          ActiveRecord::Base.connection.execute(
              "INSERT INTO help_boxes (page, action, content)
              SELECT page, action, content
              FROM helpbox"
          )
        end
      end
    end
  end
end
