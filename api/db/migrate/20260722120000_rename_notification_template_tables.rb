class RenameNotificationTemplateTables < ActiveRecord::Migration[8.1]
  def up
    rename_table :mail_recipients, :email_recipients
    rename_table :mail_templates, :notification_templates
    rename_table :mail_template_recipients, :notification_template_email_recipients
    rename_table :mail_template_translations, :notification_template_variants
    rename_table :user_mail_role_recipients, :user_email_role_recipients
    rename_table :user_mail_template_recipients, :user_notification_template_recipients

    rename_column :notification_template_email_recipients, :mail_recipient_id, :email_recipient_id
    rename_column :notification_template_email_recipients, :mail_template_id, :notification_template_id
    rename_column :notification_template_variants, :mail_template_id, :notification_template_id
    rename_column :notification_template_variants, :text_plain, :text
    rename_column :notification_template_variants, :text_html, :html
    change_column_null :notification_template_variants, :from, true
    change_column_null :notification_template_variants, :subject, true
    rename_column :user_notification_template_recipients, :mail_template_id, :notification_template_id
    rename_column :mail_logs, :mail_template_id, :notification_template_id
    if column_exists?(:event_routes, :email_template_name)
      rename_column :event_routes, :email_template_name, :template_name
    end

    add_column :notification_template_variants, :protocol, :integer, null: false, default: 0
    add_column :notification_template_variants, :options, :text, null: true

    remove_index :notification_template_email_recipients,
                 name: :mail_template_recipients_unique,
                 if_exists: true
    add_index :notification_template_email_recipients,
              %i[notification_template_id email_recipient_id],
              unique: true,
              name: :notification_template_email_recipients_unique

    remove_index :notification_template_variants,
                 name: :mail_template_translation_unique,
                 if_exists: true
    add_index :notification_template_variants,
              %i[notification_template_id protocol language_id],
              unique: true,
              name: :notification_template_variants_unique

    remove_index :user_notification_template_recipients,
                 name: :user_id_mail_template_id,
                 if_exists: true
    add_index :user_notification_template_recipients,
              %i[user_id notification_template_id],
              unique: true,
              name: :user_id_notification_template_id
  end

  def down
    remove_index :notification_template_email_recipients,
                 name: :notification_template_email_recipients_unique,
                 if_exists: true
    add_index :notification_template_email_recipients,
              %i[notification_template_id email_recipient_id],
              unique: true,
              name: :mail_template_recipients_unique

    execute 'DELETE FROM notification_template_variants WHERE protocol != 0'
    remove_index :notification_template_variants,
                 name: :notification_template_variants_unique,
                 if_exists: true
    add_index :notification_template_variants,
              %i[notification_template_id language_id],
              unique: true,
              name: :mail_template_translation_unique

    remove_index :user_notification_template_recipients,
                 name: :user_id_notification_template_id,
                 if_exists: true
    add_index :user_notification_template_recipients,
              %i[user_id notification_template_id],
              unique: true,
              name: :user_id_mail_template_id

    remove_column :notification_template_variants, :options
    remove_column :notification_template_variants, :protocol
    change_column_null :notification_template_variants, :subject, false
    change_column_null :notification_template_variants, :from, false

    if column_exists?(:event_routes, :template_name)
      rename_column :event_routes, :template_name, :email_template_name
    end
    rename_column :mail_logs, :notification_template_id, :mail_template_id
    rename_column :user_notification_template_recipients, :notification_template_id, :mail_template_id
    rename_column :notification_template_variants, :html, :text_html
    rename_column :notification_template_variants, :text, :text_plain
    rename_column :notification_template_variants, :notification_template_id, :mail_template_id
    rename_column :notification_template_email_recipients, :notification_template_id, :mail_template_id
    rename_column :notification_template_email_recipients, :email_recipient_id, :mail_recipient_id

    rename_table :user_notification_template_recipients, :user_mail_template_recipients
    rename_table :user_email_role_recipients, :user_mail_role_recipients
    rename_table :notification_template_variants, :mail_template_translations
    rename_table :notification_template_email_recipients, :mail_template_recipients
    rename_table :notification_templates, :mail_templates
    rename_table :email_recipients, :mail_recipients
  end
end
