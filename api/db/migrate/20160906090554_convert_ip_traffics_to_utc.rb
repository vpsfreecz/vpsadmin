class ConvertIpTrafficsToUtc < ActiveRecord::Migration
  def up
    %i(ip_recent_traffics ip_traffics ip_traffic_monthly_summaries).each do |t|
      ActiveRecord::Base.connection.execute("
          UPDATE #{t}
          SET created_at = CONVERT_TZ(created_at, 'Europe/Prague', 'UTC')
      ")
    end
  end

  def down
    %i(ip_recent_traffics ip_traffics ip_traffic_monthly_summaries).each do |t|
      ActiveRecord::Base.connection.execute("
          UPDATE #{t}
          SET created_at = CONVERT_TZ(created_at, 'UTC', 'Europe/Prague')
      ")
    end
  end
end
