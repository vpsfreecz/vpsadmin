class RemoveIpTraffics < ActiveRecord::Migration[6.1]
  def change
    drop_table :ip_recent_traffics
    drop_table :ip_traffic_live_monitors
    drop_table :ip_traffics
    # drop_table :ip_traffic_monthly_summaries # TODO: remove in the future
  end
end
