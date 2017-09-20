class AddMailing < ActiveRecord::Migration
  def change
    create_table :mail_recipients do |t|
      t.string     :label,            null: false, limit: 100
      t.string     :to,               null: false, limit: 500
      t.string     :cc,               null: true,  limit: 500
      t.string     :bcc,              null: true,  limit: 500
    end

    create_table :mail_templates do |t|
      t.string     :name,             null: false, limit: 100
      t.string     :label,            null: false, limit: 100
      t.string     :from,             null: false, limit: 255
      t.string     :reply_to,         null: true,  limit: 255
      t.string     :return_path,      null: true,  limit: 255
      t.string     :subject,          null: false, limit: 255
      t.text       :text_plain,       null: true
      t.text       :text_html,        null: true
      t.timestamps
    end

    add_index :mail_templates, :name, unique: true

    create_table :mail_template_recipients do |t|
      t.references :mail_template,    null: false
      t.references :mail_recipient,   null: false
    end

    add_index :mail_template_recipients, [:mail_template_id, :mail_recipient_id],
              unique: true, name: :mail_template_recipients_unique

    create_table :mail_logs do |t|
      t.references :user,             null: true
      t.string     :to,               null: false, limit: 500
      t.string     :cc,               null: false, limit: 500
      t.string     :bcc,              null: false, limit: 500
      t.string     :from,             null: false, limit: 255
      t.string     :reply_to,         null: true,  limit: 255
      t.string     :return_path,      null: true,  limit: 255
      t.string     :message_id,       null: true,  limit: 255
      t.string     :in_reply_to,      null: true,  limit: 255
      t.string     :references,       null: true,  limit: 255
      t.string     :subject,          null: false, limit: 255
      t.text       :text_plain,       null: true
      t.text       :text_html,        null: true
      t.references :mail_template,    null: true
      t.references :transaction,      null: true
      t.timestamps
    end
  end
end
