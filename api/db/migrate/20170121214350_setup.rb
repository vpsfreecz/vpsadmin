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

    create_table :user_payments do |t|
      t.references  :incoming_payment, null: true
      t.references  :user,             null: false
      t.integer     :amount,           null: false
      t.datetime    :created_at,       null: false
      t.datetime    :from_date,        null: false
      t.datetime    :to_date,          null: false
    end

    add_index :user_payments, :incoming_payment_id
    add_index :user_payments, :user_id
  end
end
