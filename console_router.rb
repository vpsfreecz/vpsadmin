#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/vpsadmind'

require 'socket'
require 'optparse'

require 'rubygems'
require 'sinatra'
require 'eventmachine'
require 'json'
require 'base64'

module VpsAdmind
  module ConsoleRouter ; end

  class ConsoleRouter::Console < EventMachine::Connection
    attr_accessor :buf, :last_access, :w, :h

    def initialize(veid, params, router)
      @veid = veid
      @session = params[:session]
      @w = params[:width]
      @h = params[:height]
      @router = router
      @buf = ""
      update_access
    end

    def post_init
      send_data({
          session: @session,
          width: @w,
          height: @h,
      }.to_json + "\n")
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

  class ConsoleRouter::Router
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
          @connections.each do |veid, console|
            if (console.last_access.to_i + 60) < Time.new.to_i
              console.close_connection
            end
          end

          @sessions.delete_if do |veid, sessions|
            sessions.delete_if do |s|
              t = Time.now.utc.to_i
              s[:expiration] < t && (s[:last_access] + 300) < t
            end

            sessions.empty?
          end
        end

        @timer = true
      end

      unless @connections.include?(veid)
        st = @db.prepared_st(
            'SELECT server_ip4
            FROM servers
            INNER JOIN vps ON vps_server = server_id
            WHERE vps_id = ?',
            veid
        )

        @connections[veid] = EventMachine.connect(
            st.fetch[0],
            8081,
            ConsoleRouter::Console, veid, params, self
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

      st = @db.prepared_st(
          'SELECT UNIX_TIMESTAMP(expiration)
          FROM vps_console
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
  end
end

$CFG = VpsAdmind::AppConfig.new(ENV["config"] || "/etc/vpsadmin/vpsadmind.yml")

unless $CFG.load
  exit(false)
end

r = VpsAdmind::ConsoleRouter::Router.new

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
    r.send_cmd(v, params)

    {
        data: Base64.encode64(r.get_console(v, params[:session])),
        session: true
    }.to_json

  else
    {data: "Access denied, invalid session", session: nil}.to_json
  end
end
