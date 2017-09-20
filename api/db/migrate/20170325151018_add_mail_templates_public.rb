class AddMailTemplatesPublic < ActiveRecord::Migration
  def change
    add_column :mail_templates, :user_visibility, :integer, null: false, default: 0
  end
end
