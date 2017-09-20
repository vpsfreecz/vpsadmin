class AddIpTrafficLiveMonitor < ActiveRecord::Migration
  ROLES = %i(public private)
  PROTOCOLS = %i(tcp udp other)

  def change
    create_table :ip_traffic_live_monitors do |t|
      t.references  :ip_address,          null: false

      cols(t)

      ROLES.each do |r|
        cols(t, r)

        PROTOCOLS.each do |proto|
          cols(t, r, proto)
        end
      end

      t.datetime    :updated_at,          null: false
      t.integer     :delta,               null: true
    end

    add_index :ip_traffic_live_monitors, :ip_address_id, unique: true
  end

  def cols(t, *name)
    %i(packets bytes).each do |stat|
      col(t, *(name + [stat]))

      %i(in out).each do |dir|
        col(t, *(name + [stat, dir]))
      end
    end
  end

  def col(t, *name)
    t.integer name.join('_'), null: false, limit: 8, unsigned: true, default: 0
  end
end
