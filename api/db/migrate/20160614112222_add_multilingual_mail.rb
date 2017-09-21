class AddMultilingualMail < ActiveRecord::Migration
  class Language < ActiveRecord::Base ; end

  class MailTemplate < ActiveRecord::Base
    has_many :mail_template_translations
  end

  class MailTemplateTranslation < ActiveRecord::Base
    belongs_to :language
    belongs_to :mail_template
  end

  def up
    create_table :languages do |t|
      t.string     :code,             null: false, limit: 2
      t.string     :label,            null: false, limit: 100
    end

    add_index :languages, :code, unique: true

    create_table :mail_template_translations do |t|
      t.references :mail_template,    null: false
      t.references :language,         null: false
      t.string     :from,             null: false, limit: 255
      t.string     :reply_to,         null: true,  limit: 255
      t.string     :return_path,      null: true,  limit: 255
      t.string     :subject,          null: false, limit: 255
      t.text       :text_plain,       null: true
      t.text       :text_html,        null: true
      t.timestamps
    end

    add_index :mail_template_translations, [:mail_template_id, :language_id], unique: true,
              name: :mail_template_translation_unique
    add_column :members, :language_id, :integer, default: 1

    lang_en = Language.create!(code: 'en', label: 'English')

    MailTemplate.all.each do |tpl|
      tpl.mail_template_translations << MailTemplateTranslation.new(
          language: lang_en,
          from: tpl.from,
          reply_to: tpl.reply_to,
          return_path: tpl.return_path,
          subject: tpl.subject,
          text_plain: tpl.text_plain,
          text_html: tpl.text_html,
      )
    end

    remove_column :mail_templates, :from
    remove_column :mail_templates, :reply_to
    remove_column :mail_templates, :return_path
    remove_column :mail_templates, :subject
    remove_column :mail_templates, :text_plain
    remove_column :mail_templates, :text_html
  end

  def down
    add_column :mail_templates, :from,        :string, null: false, limit: 255
    add_column :mail_templates, :reply_to,    :string, null: true,  limit: 255
    add_column :mail_templates, :return_path, :string, null: true,  limit: 255
    add_column :mail_templates, :subject,     :string, null: false, limit: 255
    add_column :mail_templates, :text_plain,  :text,   null: true
    add_column :mail_templates, :text_html,   :text,   null: true

    MailTemplateTranslation.all.group(
        'mail_template_id'
    ).order(
        'mail_template_id, id'
    ).each do |tr|
      tr.mail_template.update!(
          from: tr.from,
          reply_to: tr.reply_to,
          return_path: tr.return_path,
          subject: tr.subject,
          text_plain: tr.text_plain,
          text_html: tr.text_html,
      )
    end

    drop_table :mail_template_translations
    drop_table :languages
    remove_column :members, :language_id
  end
end
