class RelaxNotificationTemplateVariantEmailColumns < ActiveRecord::Migration[8.1]
  def up
    change_column_null :notification_template_variants, :from, true
    change_column_null :notification_template_variants, :subject, true
  end

  def down
    execute 'DELETE FROM notification_template_variants WHERE protocol != 0'
    change_column_null :notification_template_variants, :subject, false
    change_column_null :notification_template_variants, :from, false
  end
end
