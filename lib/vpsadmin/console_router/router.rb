module VpsAdmin::ConsoleRouter
  class Router
    def initialize
      @connections = {}
      @sessions = {}
    end

    def api_url
      rs = db.query("SELECT cfg_value FROM sysconfig WHERE cfg_name = 'api_url'")
      JSON.parse("{ \"v\": #{rs.fetch_row.first} }", symbolize_names: true)[:v]
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
        data[:keys] = Base64.encode64(params[:keys])
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

          if @last_db_access && @db
            if @last_db_access + 30 < t
              puts "Disconnecting from db"
              @db.close
              @db = nil
            end
          end

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
        st = db.prepared_st(
            'SELECT ip_addr
            FROM nodes
            INNER JOIN vps ON vps_server = nodes.id
            WHERE vps_id = ?',
            veid
        )

        @connections[veid] = EventMachine.connect(
            st.fetch[0],
            8081,
            Console, veid, params, self
        )

        st.close
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

      st = db.prepared_st(
          'SELECT UNIX_TIMESTAMP(expiration)
          FROM vps_consoles
          WHERE vps_id = ? AND token = ? AND expiration > ?',
          veid,
          session,
          Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      )

      if st.num_rows == 1
        @sessions[veid] ||= []
        @sessions[veid] << {
            session: session,
            expiration: st.fetch[0].to_i,
            last_access: Time.now.utc.to_i,
            buf: ''
        }
        st.close
        return true
      end

      st.close
      false
    end

    def db
      @last_db_access = Time.now
      return @db if @db
      @db = VpsAdmind::Db.new
    end
  end
end
