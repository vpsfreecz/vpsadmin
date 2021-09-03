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

    def get_console(veid, session)
      check_connection(veid, session)

      buf = @connections[veid].buf
      s_id = -1

      @sessions[veid].each do |s|
        if s[:session] == session
          s_id = @sessions[veid].index(s)
          next
        end

        s[:buf] += buf
      end

      @connections[veid].buf = ""

      buf = @sessions[veid][s_id][:buf] + buf
      @sessions[veid][s_id][:buf] = ""

      buf
    end

    def send_cmd(veid, params)
      check_connection(veid, params)
      s_id = -1

      @sessions[veid].each do |s|
        if s[:session] == params[:session]
          s_id = @sessions[veid].index(s)
          break
        end
      end

      conn = @connections[veid]

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

      @sessions[veid][s_id][:last_access] = Time.new.to_i

      conn.send_data(data.to_json + "\n")
    end

    def check_connection(veid, params)
      unless @timer
        EventMachine.add_periodic_timer(60) do
          t = Time.now
          t_i = t.to_i

          @connections.each do |veid, console|
            if (console.last_access.to_i + 60) < t_i
              console.close_connection
            end
          end

          @sessions.delete_if do |veid, sessions|
            sessions.delete_if do |s|
              s[:expiration] < t_i && (s[:last_access] + 300) < t_i
            end

            sessions.empty?
          end
        end

        @timer = true
      end

      unless @connections.include?(veid)
        n = ::Node.select('ip_addr').joins(:vpses).where(vpses: {id: veid})

        @connections[veid] = EventMachine.connect(
          n.ip_addr,
          8081,
          Console, veid, params, self
        )
      end

      @connections[veid].update_access
    end

    def disconnected(veid)
      @connections.delete(veid)
      @sessions.delete(veid)
    end

    def check_session(veid, session)
      return false unless session && veid

      if @sessions.include?(veid)
        t = Time.now.utc.to_i

        @sessions[veid].each do |s|
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
        .where(vps_id: veid, token: session)
        .where('expiration > ?', Time.now.utc)
        .take

      if console
        @sessions[veid] ||= []
        @sessions[veid] << {
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
