class RefactorOsTemplates < ActiveRecord::Migration
  def change
    rename_table :cfg_templates, :os_templates
    rename_column :os_templates, :templ_id, :id
    rename_column :os_templates, :templ_name, :name
    rename_column :os_templates, :templ_label, :label
    rename_column :os_templates, :templ_info, :info
    rename_column :os_templates, :templ_enabled, :enabled
    rename_column :os_templates, :templ_supported, :supported
    rename_column :os_templates, :templ_order, :order
  end
end
