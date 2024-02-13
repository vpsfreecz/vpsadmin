class Setup < ActiveRecord::Migration
  def change
    create_table :incoming_payments do |t|
      t.string      :transaction_id,   null: false, limit: 30
      t.integer     :state,            null: false, default: 0
      t.date        :date,             null: false
      t.decimal     :amount,           null: false, precision: 10, scale: 2
      t.string      :currency,         null: false, limit: 3
      t.decimal     :src_amount,       null: true,  precision: 10, scale: 2
      t.string      :src_currency,     null: true,  limit: 3
      t.string      :account_name,     null: true,  limit: 100
      t.string      :user_ident,       null: true,  limit: 100
      t.string      :user_message,     null: true,  limit: 255
      t.string      :vs,               null: true,  limit: 100
      t.string      :ks,               null: true,  limit: 100
      t.string      :ss,               null: true,  limit: 100
      t.string      :transaction_type, null: false, limit: 100
      t.string      :comment,          null: true,  limit: 255
      t.datetime    :created_at,       null: false
    end

    add_index :incoming_payments, :transaction_id, unique: true
    add_index :incoming_payments, :vs
    add_index :incoming_payments, :ks
    add_index :incoming_payments, :ss

    create_table :user_accounts do |t|
      t.references  :user,             null: false
      t.integer     :monthly_payment,  null: false, default: 0
      t.datetime    :paid_until,       null: true
      t.datetime    :updated_at
    end

    add_index :user_accounts, :user_id, unique: true

    create_table :user_payments do |t|
      t.references  :incoming_payment, null: true
      t.references  :user,             null: false
      t.references  :accounted_by,     null: true
      t.integer     :amount,           null: false
      t.datetime    :created_at,       null: false
      t.datetime    :from_date,        null: false
      t.datetime    :to_date,          null: false
    end

    add_index :user_payments, :incoming_payment_id, unique: true
    add_index :user_payments, :user_id
    add_index :user_payments, :accounted_by_id

    reversible do |dir|
      dir.up do
        if ENV['FROM_VPSADMIN1']
          ActiveRecord::Base.connection.execute(
            "INSERT INTO user_accounts (user_id, monthly_payment, paid_until)
              SELECT id, monthly_payment, paid_until
              FROM users
              WHERE object_state < 3
              ORDER BY id"
          )

          if table_exists?(:members_payments)
            ActiveRecord::Base.connection.execute(
              "INSERT INTO user_payments (
                  user_id,
                  accounted_by_id,
                  amount,
                  created_at,
                  from_date,
                  to_date
                )
                SELECT
                  m_id,
                  acct_m_id,
                  CASE change_from
                  WHEN 0 THEN
                    IF(
                      change_to = 0 OR u.created_at IS NULL OR change_to < UNIX_TIMESTAMP(u.created_at),
                      0,
                      u.monthly_payment * ((change_to - UNIX_TIMESTAMP(u.created_at)) DIV (60*60*24*30))
                    )
                  ELSE
                    u.monthly_payment * ((change_to - change_from) DIV (60*60*24*30))
                  END,
                  FROM_UNIXTIME(`timestamp`),
                  IFNULL(FROM_UNIXTIME(change_from), NOW()),
                  IFNULL(FROM_UNIXTIME(change_to), DATE_ADD(NOW(), INTERVAL 100 YEAR))
                FROM members_payments p
                INNER JOIN users u ON p.m_id = u.id"
            )
          end

        else
          ActiveRecord::Base.connection.execute(
            "INSERT INTO user_accounts (user_id, monthly_payment)
              SELECT id, 0
              FROM users
              WHERE object_state < 3
              ORDER BY id"
          )
        end
      end
    end
  end
end
