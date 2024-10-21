class AddOsTemplateConfig < ActiveRecord::Migration[7.1]
  def change
    add_column :os_templates, :config, :text, null: false, default: ''
  end
end
