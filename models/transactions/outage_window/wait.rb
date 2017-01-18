module Transactions::OutageWindow
  class Wait < ::Transaction
    t_name :outage_window_wait
    t_type 2101
    queue :outage

    # @param vps [::Vps]
    # @param reserve_time [Integer] number of minutes that must be left in the window
    def params(vps, reserve_time)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      windows = []

      vps.vps_outage_windows.where(is_open: true).order('weekday').each do |w|
        windows << {
            weekday: w.weekday,
            opens_at: w.opens_at,
            closes_at: w.closes_at,
        }
      end

      {
          windows: windows,
          reserve_time: reserve_time,
      }
    end
  end
end
