class SetVpsOsTemplateIdNull < ActiveRecord::Migration[7.2]
  def change
    change_column_null :vpses, :os_template_id, true
    change_column_default :vpses, :os_template_id, from: 1, to: nil
  end
end
