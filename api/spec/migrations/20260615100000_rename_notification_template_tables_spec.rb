# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260615100000_rename_notification_template_tables')

RSpec.describe RenameNotificationTemplateTables do
  def define_old_schema
    define_schema do
      create_table :mail_recipients, id: { type: :integer, unsigned: true } do |t|
        t.string :label, limit: 100, null: false
        t.string :to, limit: 500
        t.string :cc, limit: 500
        t.string :bcc, limit: 500
      end

      create_table :mail_templates, id: { type: :integer, unsigned: true } do |t|
        t.string :name, limit: 100, null: false
        t.string :label, limit: 255
      end

      create_table :mail_template_recipients, id: { type: :integer, unsigned: true } do |t|
        t.integer :mail_template_id, null: false
        t.integer :mail_recipient_id, null: false
      end
      add_index :mail_template_recipients, %i[mail_template_id mail_recipient_id],
                unique: true, name: :mail_template_recipients_unique

      create_table :mail_template_translations, id: { type: :integer, unsigned: true } do |t|
        t.integer :mail_template_id, null: false
        t.integer :language_id, null: false
        t.string :from, limit: 255, null: false
        t.string :subject, limit: 255, null: false
        t.text :text_plain
        t.text :text_html
      end
      add_index :mail_template_translations, %i[mail_template_id language_id],
                unique: true, name: :mail_template_translation_unique

      create_table :user_mail_role_recipients, id: { type: :integer, unsigned: true } do |t|
        t.integer :user_id, null: false
        t.string :role, limit: 100, null: false
        t.string :to, limit: 500
      end

      create_table :user_mail_template_recipients, id: { type: :integer, unsigned: true } do |t|
        t.integer :user_id, null: false
        t.integer :mail_template_id, null: false
        t.string :to, limit: 500
        t.boolean :enabled, null: false, default: true
      end
      add_index :user_mail_template_recipients, %i[user_id mail_template_id],
                unique: true, name: :user_id_mail_template_id

      create_table :mail_logs do |t|
        t.integer :mail_template_id
      end

      create_table :event_routes do |t|
        t.string :email_template_name
      end
    end
  end

  def seed_old_rows
    template_id = insert_row(:mail_templates, name: 'daily_report', label: 'Daily report')
    recipient_id = insert_row(:mail_recipients, label: 'admins', to: 'admin@example.test')
    insert_row(:mail_template_recipients, mail_template_id: template_id, mail_recipient_id: recipient_id)
    insert_row(
      :mail_template_translations,
      mail_template_id: template_id,
      language_id: 1,
      from: 'support@example.test',
      subject: 'Report',
      text_plain: 'plain',
      text_html: '<p>html</p>'
    )
    insert_row(:user_mail_role_recipients, user_id: 1, role: 'admin', to: 'admin@example.test')
    insert_row(
      :user_mail_template_recipients,
      user_id: 1,
      mail_template_id: template_id,
      to: 'custom@example.test',
      enabled: true
    )
    insert_row(:mail_logs, mail_template_id: template_id)
    insert_row(:event_routes, email_template_name: 'daily_report')
  end

  it 'renames legacy mail template tables, columns and indexes' do
    define_old_schema
    seed_old_rows

    migrate_up!

    expect(table_exists?(:email_recipients)).to be(true)
    expect(table_exists?(:notification_templates)).to be(true)
    expect(table_exists?(:notification_template_email_recipients)).to be(true)
    expect(table_exists?(:notification_template_variants)).to be(true)
    expect(table_exists?(:user_email_role_recipients)).to be(true)
    expect(table_exists?(:user_notification_template_recipients)).to be(true)

    expect(column_exists?(:notification_template_email_recipients, :notification_template_id)).to be(true)
    expect(column_exists?(:notification_template_email_recipients, :email_recipient_id)).to be(true)
    expect(column_exists?(:notification_template_variants, :notification_template_id)).to be(true)
    expect(column_exists?(:notification_template_variants, :text)).to be(true)
    expect(column_exists?(:notification_template_variants, :html)).to be(true)
    expect(column_exists?(:notification_template_variants, :protocol)).to be(true)
    expect(column_exists?(:notification_template_variants, :options)).to be(true)
    expect(column_exists?(:mail_logs, :notification_template_id)).to be(true)
    expect(column_exists?(:event_routes, :template_name)).to be(true)
    expect(index_exists?(:notification_template_email_recipients,
                         :notification_template_email_recipients_unique)).to be(true)
    expect(index_exists?(:notification_template_variants, :notification_template_variants_unique)).to be(true)
    expect(index_exists?(:user_notification_template_recipients, :user_id_notification_template_id)).to be(true)

    variant = rows(:notification_template_variants).first
    expect(variant.fetch('protocol').to_i).to eq(0)
    expect(variant.fetch('options')).to be_nil
  end

  it 'rolls back to the legacy mail template schema' do
    define_old_schema
    seed_old_rows
    migrate_up!

    insert_row(
      :notification_template_variants,
      notification_template_id: 1,
      language_id: 2,
      from: 'bot@example.test',
      subject: 'SMS',
      text: 'text',
      html: nil,
      protocol: 1,
      options: '{}'
    )

    migrate_down!

    expect(table_exists?(:mail_recipients)).to be(true)
    expect(table_exists?(:mail_templates)).to be(true)
    expect(table_exists?(:mail_template_recipients)).to be(true)
    expect(table_exists?(:mail_template_translations)).to be(true)
    expect(table_exists?(:user_mail_role_recipients)).to be(true)
    expect(table_exists?(:user_mail_template_recipients)).to be(true)

    expect(column_exists?(:mail_template_recipients, :mail_template_id)).to be(true)
    expect(column_exists?(:mail_template_recipients, :mail_recipient_id)).to be(true)
    expect(column_exists?(:mail_template_translations, :mail_template_id)).to be(true)
    expect(column_exists?(:mail_template_translations, :text_plain)).to be(true)
    expect(column_exists?(:mail_template_translations, :text_html)).to be(true)
    expect(column_exists?(:mail_template_translations, :protocol)).to be(false)
    expect(column_exists?(:mail_logs, :mail_template_id)).to be(true)
    expect(column_exists?(:event_routes, :email_template_name)).to be(true)
    expect(index_exists?(:mail_template_recipients, :mail_template_recipients_unique)).to be(true)
    expect(index_exists?(:mail_template_translations, :mail_template_translation_unique)).to be(true)
    expect(index_exists?(:user_mail_template_recipients, :user_id_mail_template_id)).to be(true)

    expect(row_count(:mail_template_translations)).to eq(1)
  end
end
