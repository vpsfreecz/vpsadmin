class AddVpsesEnableOsTemplateAutoUpdate < ActiveRecord::Migration[7.2]
  def change
    add_column :vpses, :enable_os_template_auto_update, :boolean, null: false, default: true
  end
end
