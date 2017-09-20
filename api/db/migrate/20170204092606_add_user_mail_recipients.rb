class AddUserMailRecipients < ActiveRecord::Migration
  class MailTemplate < ActiveRecord::Base ; end

  def change
    create_table :user_mail_role_recipients do |t|
      t.references :user,             null: false
      t.string     :role,             null: false, limit: 100
      t.string     :to,               null: true,  limit: 500
    end

    add_index :user_mail_role_recipients, %i(user_id role), unique: true
    add_index :user_mail_role_recipients, :user_id

    create_table :user_mail_template_recipients do |t|
      t.references :user,             null: false
      t.references :mail_template,    null: false
      t.string     :to,               null: false, limit: 500
      t.boolean    :enabled,          null: false, default: true
    end
    
    add_index :user_mail_template_recipients, %i(user_id mail_template_id),
        unique: true, name: :user_id_mail_template_id
    add_index :user_mail_template_recipients, :user_id

    add_column :mail_templates, :template_id, :string, null: true, limit: 100

    reversible do |dir|
      dir.up do
        MailTemplate.all.each do |tpl|
          tpl.template_id = case tpl.name
          when /\Aexpiration_/
            'expiration_warning'

          else
            tpl.name
          end

          tpl.save!
        end

        change_column_null :mail_templates, :template_id, false
      end
    end
  end
end
