module VpsAdmin::ConsoleRouter
  class Router
    def initialize
      @connections = {}
      @sessions = {}
    end

    def api_url
      ::SysConfig.select('value').where(
        category: 'core',
        name: 'api_url',
      ).take!.value
    end

    def get_console(vps_id, session)
      check_connection(vps_id, session)

      buf = @connections[vps_id].buf
      s_id = -1

      @sessions[vps_id].each do |s|
        if s[:session] == session
          s_id = @sessions[vps_id].index(s)
          next
        end

        s[:buf] += buf
      end

      @connections[vps_id].buf = ""

      buf = @sessions[vps_id][s_id][:buf] + buf
      @sessions[vps_id][s_id][:buf] = ""

      buf
    end

    def send_cmd(vps_id, params)
      check_connection(vps_id, params)
      s_id = -1

      @sessions[vps_id].each do |s|
        if s[:session] == params[:session]
          s_id = @sessions[vps_id].index(s)
          break
        end
      end

      conn = @connections[vps_id]

      data = {}

      if params[:keys] && !params[:keys].empty?
        data[:keys] = Base64.strict_encode64(params[:keys])
      end

      w = params[:width].to_i
      h = params[:height].to_i

      if conn.w != w || conn.h != h
        conn.w = w
        conn.h = h
        data[:width] = w
        data[:height] = h
      end

      return if data.empty?

      @sessions[vps_id][s_id][:last_access] = Time.new.to_i

      conn.send_data(data.to_json + "\n")
    end

    def check_connection(vps_id, params)
      unless @timer
        EventMachine.add_periodic_timer(60) do
          t = Time.now
          t_i = t.to_i

          @connections.each do |vps_id, console|
            if (console.last_access.to_i + 60) < t_i
              console.close_connection
            end
          end

          @sessions.delete_if do |vps_id, sessions|
            sessions.delete_if do |s|
              s[:expiration] < t_i && (s[:last_access] + 300) < t_i
            end

            sessions.empty?
          end
        end

        @timer = true
      end

      unless @connections.include?(vps_id)
        n = ::Node.select('ip_addr').joins(:vpses).where(vpses: {id: vps_id}).take!

        @connections[vps_id] = EventMachine.connect(
          n.ip_addr,
          8081,
          Console, vps_id, params, self
        )
      end

      @connections[vps_id].update_access
    end

    def disconnected(vps_id)
      @connections.delete(vps_id)
      @sessions.delete(vps_id)
    end

    def check_session(vps_id, session)
      return false unless session && vps_id

      if @sessions.include?(vps_id)
        t = Time.now.utc.to_i

        @sessions[vps_id].each do |s|
          if s[:session] == session
            if (s[:last_access] + 600) < t
              return false

            else
              return true
            end
          end
        end
      end

      console = ::VpsConsole
        .select('UNIX_TIMESTAMP(expiration) AS expiration_ts')
        .where(vps_id: vps_id, token: session)
        .where('expiration > ?', Time.now.utc)
        .take

      if console
        @sessions[vps_id] ||= []
        @sessions[vps_id] << {
          session: session,
          expiration: console.expiration_ts,
          last_access: Time.now.utc.to_i,
          buf: ''
        }
        return true
      end

      false
    end
  end
end
