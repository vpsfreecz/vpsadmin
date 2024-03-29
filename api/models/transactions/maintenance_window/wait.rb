module Transactions::MaintenanceWindow
  class Wait < ::Transaction
    t_name :maintenance_window_wait
    t_type 2101
    queue :outage

    # @param vps [::Vps]
    # @param reserve_time [Integer] number of minutes that must be left in the window
    # @param maintenance_windows [Array<::VpsMaintenanceWindow>, nil]
    def params(vps, reserve_time, maintenance_windows: nil)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      maintenance_windows ||= vps.vps_maintenance_windows.where(is_open: true).order('weekday')
      window_hashes = []

      maintenance_windows.each do |w|
        window_hashes << {
          weekday: w.weekday,
          opens_at: w.opens_at,
          closes_at: w.closes_at
        }
      end

      {
        windows: window_hashes,
        reserve_time:
      }
    end
  end
end
