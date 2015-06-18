#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/vpsadmind'

require 'socket'
require 'optparse'

require 'rubygems'
require 'sinatra'
require 'eventmachine'
require 'json'

module VpsAdmind
  class Console < EventMachine::Connection
    attr_accessor :buf, :last_access

    def initialize(veid, session, router)
      @veid = veid
      @session = session
      @router = router
      @buf = ""
      update_access
    end

    def post_init
      send_data(@session)
    end

    def receive_data(data)
      @buf += data
    end

    def unbind
      @router.disconnected(@veid)
    end

    def update_access
      @last_access = Time.new
    end
  end

  class Router
    def initialize
      @connections = {}
      @sessions = {}
      @db = Db.new
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

    def send_cmd(veid, session, cmd)
      check_connection(veid, session)

      s_id = -1

      @sessions[veid].each do |s|
        if s[:session] == session
          s_id = @sessions[veid].index(s)
          break
        end
      end

      @sessions[veid][s_id][:last_access] = Time.new.to_i

      @connections[veid].send_data(cmd)
    end

    def check_connection(veid, session)
      unless @timer
        EventMachine.add_periodic_timer(60) do
          @connections.each do |veid, console|
            if (console.last_access.to_i + 60) < Time.new.to_i
              console.close_connection
            end
          end

          @sessions.delete_if do |veid, sessions|
            sessions.delete_if do |s|
              t = Time.new.to_i
              s[:expiration] < t && (s[:last_access] + 300) < t
            end

            sessions.empty?
          end
        end

        @timer = true
      end

      unless @connections.include?(veid)
        st = @db.prepared_st("SELECT server_ip4 FROM servers INNER JOIN vps ON vps_server = server_id WHERE vps_id = ?", veid)

        @connections[veid] = EventMachine.connect(st.fetch[0], 8081, Console, veid, session, self)

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
        t = Time.new.to_i
        @sessions[veid].each do |s|
          if s[:session] == session
            if s[:expiration] > t || (s[:last_access] + 300) > t
              return true
            else
              return false
            end
          end
        end
      end

      st = @db.prepared_st(
          'SELECT UNIX_TIMESTAMP(expiration) FROM vps_console WHERE vps_id = ? AND token = ? AND expiration > ?',
          veid,
          session,
          Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      )

      if st.num_rows == 1
        @sessions[veid] ||= []
        @sessions[veid] << {:session => session, :expiration => st.fetch[0].to_i, :last_access => Time.now.utc.to_i, :buf => ""}
        st.close
        return true
      end

      st.close
      false
    end
  end
end

$CFG = VpsAdmind::AppConfig.new(ENV["config"] || "/etc/vpsadmin/vpsadmind.yml")

unless $CFG.load
  exit(false)
end

r = VpsAdmind::Router.new

configure do
  set :protection, :except => :frame_options
end

get '/console/:veid' do |veid|
  v = veid.to_i

  if r.check_session(v, params[:session])
    erb :console, :locals => {:veid => v, :session => params[:session]}
  else
    "Access denied, invalid session"
  end
end

post '/console/feed/:veid' do |veid|
  v = veid.to_i

  if r.check_session(v, params[:session])
    r.send_cmd(v, params[:session], params[:keys]) if params[:keys]
    {:data => r.get_console(v, params[:session]), :session => params[:session]}.to_json
  else
    {:data => "Access denied, invalid session", :session => nil}.to_json
  end
end
