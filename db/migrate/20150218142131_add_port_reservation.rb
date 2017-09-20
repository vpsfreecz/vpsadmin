class AddPortReservation < ActiveRecord::Migration
  class Node < ActiveRecord::Base
    self.table_name = 'servers'
    self.primary_key = 'server_id'
  end

  class PortReservation < ActiveRecord::Base  ; end

  def change
    create_table :port_reservations do |t|
      t.references :node,              null: false
      t.string     :addr,              null: true,  limit: 100
      t.integer    :port,              null: false
      t.references :transaction_chain, null: true
    end

    add_index :port_reservations, [:node_id, :port], unique: true,
        name: :port_reservation_uniqueness

    reversible do |dir|
      dir.up do
        Node.all.each do |n|
          10000.times do |i|
            PortReservation.create!(
                node_id: n.id,
                port: 10000 + i
            )
          end
        end
      end
    end
  end
end
