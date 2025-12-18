# frozen_string_literal: true

require 'socket'
require 'json'
require 'rexml/document'
require 'timeout'
require 'libosctl'

module NodeCtld
  class VncProxyServer
    include OsCtl::Lib::Utils::Log

    ClientInfo = Struct.new(
      :thread,
      :peer,
      :domain_uuid,
      :domain_name,
      :connected_at,
      :rx_bytes,
      :tx_bytes,
      keyword_init: true
    )

    # How long we will wait for a VM to become active / expose VNC.
    # Set to nil to wait forever.
    DEFAULT_WAIT_FOR_VNC_TIMEOUT = 10 * 60 # seconds

    # Poll interval while waiting for a VM to become active / VNC to appear.
    DEFAULT_POLL_INTERVAL = 1.0 # seconds

    # How long to wait for TCP connect probe to succeed (per poll).
    DEFAULT_PORT_PROBE_TIMEOUT = 0.5 # seconds

    def log_type
      'vnc-server'
    end

    def initialize(
      listen_host: nil,
      listen_port: nil,
      wait_for_vnc_timeout: DEFAULT_WAIT_FOR_VNC_TIMEOUT,
      poll_interval: DEFAULT_POLL_INTERVAL,
      port_probe_timeout: DEFAULT_PORT_PROBE_TIMEOUT
    )
      @listen_host = listen_host || $CFG.get(:vnc, :host)
      @listen_port = listen_port || $CFG.get(:vnc, :port)

      @wait_for_vnc_timeout = wait_for_vnc_timeout
      @poll_interval = poll_interval
      @port_probe_timeout = port_probe_timeout

      @server = nil
      @server_thread = nil
      @stop = false

      @clients = {} # sock => ClientInfo
      @clients_mutex = Mutex.new
    end

    # Start the accept loop in a background thread and return immediately.
    def start
      return if running?

      @stop = false
      @server = TCPServer.new(@listen_host, @listen_port)

      log(:info, "listening on #{@listen_host}:#{@listen_port}")

      @server_thread = Thread.new do
        Thread.current.name = 'vnc-proxy-acceptor' if Thread.current.respond_to?(:name=)
        accept_loop
      end

      nil
    end

    # Stop accepting new connections, close all client connections and stop threads.
    def stop
      @stop = true

      if @server
        begin
          @server.close
        rescue StandardError
          # pass
        end
      end
      @server = nil

      clients = nil
      @clients_mutex.synchronize { clients = @clients.keys }

      clients.each do |sock|
        sock.close unless sock.closed?
      rescue StandardError
        # pass
      end

      infos = nil
      @clients_mutex.synchronize do
        infos = @clients.values
        @clients.clear
      end

      infos.each do |info|
        next unless info&.thread

        info.thread.kill
      rescue StandardError
        # pass
      end

      if @server_thread
        begin
          @server_thread.join(2)
        rescue StandardError
          # pass
        end
        begin
          @server_thread.kill if @server_thread.alive?
        rescue StandardError
          # pass
        end
      end
      @server_thread = nil

      log(:info, 'stopped')
      nil
    end

    def running?
      @server_thread && @server_thread.alive?
    end

    def stats
      return [] unless running?

      @clients_mutex.synchronize do
        @clients.map do |_sock, info|
          {
            peer: info.peer,
            domain_uuid: info.domain_uuid,
            domain_name: info.domain_name,
            connected_at: info.connected_at&.to_i,
            rx_bytes: info.rx_bytes,
            tx_bytes: info.tx_bytes
          }
        end
      end
    end

    private

    def accept_loop
      until @stop
        begin
          sock = @server.accept
        rescue IOError, Errno::EBADF
          break
        rescue StandardError => e
          log(:warn, "accept error: #{e.class}: #{e.message}")
          next
        end

        begin
          sock.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        rescue StandardError
          nil
        end

        peer = safe_peer(sock)
        t = Thread.new(sock, peer) do |client, client_peer|
          Thread.current.name = 'vnc-proxy-client' if Thread.current.respond_to?(:name=)
          info = ClientInfo.new(
            thread: Thread.current,
            peer: client_peer,
            connected_at: Time.now,
            rx_bytes: 0,
            tx_bytes: 0
          )
          register_client(client, info)

          begin
            handle_client(client, peer: client_peer)
          ensure
            unregister_client(client)
            begin
              client.close unless client.closed?
            rescue StandardError
              # pass
            end
          end
        end

      end
    ensure
      log(:debug, 'accept loop ended')
    end

    def register_client(sock, info)
      @clients_mutex.synchronize { @clients[sock] = info }
    end

    def unregister_client(sock)
      @clients_mutex.synchronize { @clients.delete(sock) }
    end

    def handle_client(client, peer:)
      log(:info, "connection from #{peer}")

      node_token = read_handshake_token(client)
      unless node_token
        log(:warn, "missing/invalid handshake from #{peer}")
        return
      end

      domain_uuid = authenticate_session(node_token)
      unless domain_uuid.is_a?(String) && !domain_uuid.empty?
        log(:warn, "token rejected from #{peer}")
        return
      end
      update_client_domain(client, domain_uuid)

      log(:info, "token ok from #{peer}, domain_uuid=#{domain_uuid}")

      qemu_host, qemu_port = wait_for_vnc(domain_uuid)
      log(:info, "domain_uuid=#{domain_uuid} vnc=#{qemu_host}:#{qemu_port}")

      qemu = TCPSocket.new(qemu_host, qemu_port)
      begin
        qemu.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      rescue StandardError
        nil
      end

      proxy_bidirectional(client, qemu, peer:, domain_uuid:)
    rescue Timeout::Error => e
      log(:warn, "timeout from #{peer}: #{e.message}")
    rescue JSON::ParserError
      log(:warn, "invalid JSON handshake from #{peer}")
    rescue StandardError => e
      log(:warn, "client error from #{peer}: #{e.class}: #{e.message}")
      log(:debug, e.backtrace.join("\n")) if e.backtrace
    end

    # ---- Handshake / auth ----

    # Expect first line: {"token":"..."}\n
    def read_handshake_token(client)
      line = client.gets
      return nil if line.nil? || line.bytesize > 16 * 1024

      obj = JSON.parse(line)
      tok = obj['token']
      return nil unless tok.is_a?(String) && !tok.empty?

      tok
    end

    def authenticate_session(node_token)
      RpcClient.run do |rpc|
        rpc.authenticate_vnc_session(node_token)
      end
    rescue StandardError => e
      log(:warn, "rpc auth failed: #{e.class}: #{e.message}")
      nil
    end

    # ---- Libvirt / VNC readiness ----

    def wait_for_vnc(domain_uuid)
      deadline =
        if @wait_for_vnc_timeout.nil?
          nil
        else
          Process.clock_gettime(Process::CLOCK_MONOTONIC) + @wait_for_vnc_timeout
        end

      loop do
        host, port = find_ready_vnc(domain_uuid)
        return [host, port] if host && port && port > 0

        if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise Timeout::Error, "waiting for VNC timed out (domain_uuid=#{domain_uuid})"
        end

        sleep(@poll_interval)
      end
    end

    # Returns [host, port] only when:
    # - dom.active? is true
    # - XML contains a positive VNC port
    # - the port is actually accepting TCP connections (probe)
    def find_ready_vnc(domain_uuid)
      lv = LibvirtClient.new
      dom = lv.lookup_domain_by_uuid(domain_uuid)

      active = dom.respond_to?(:active?) ? dom.active? : dom.active == 1
      return [nil, nil] unless active

      xml = dom.xml_desc
      host, port = parse_vnc_from_domain_xml(xml)
      return [nil, nil] unless host && port && port > 0

      return [host, port] if port_open?(host, port, timeout: @port_probe_timeout)

      [nil, nil]
    rescue StandardError => e
      log(:warn, "libvirt lookup failed: #{e.class}: #{e.message} (uuid=#{domain_uuid})")
      [nil, nil]
    end

    def port_open?(host, port, timeout:)
      Socket.tcp(host, port, connect_timeout: timeout, &:close)
      true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, IOError, Timeout::Error
      false
    end

    # <graphics type='vnc' port='5901' listen='127.0.0.1' .../>
    def parse_vnc_from_domain_xml(xml)
      doc = REXML::Document.new(xml)

      gfx = nil
      REXML::XPath.each(doc, '/domain/devices/graphics') do |g|
        next unless g.attributes['type'] == 'vnc'

        gfx = g
        break
      end
      return [nil, nil] unless gfx

      port_str = gfx.attributes['port']
      port = port_str.to_i if port_str

      host =
        gfx.attributes['listen'] ||
        begin
          listen_el = REXML::XPath.first(gfx, "listen[@type='address']")
          listen_el&.attributes&.[]('address')
        end ||
        '127.0.0.1'

      [host, port]
    end

    # ---- Proxying ----

    def proxy_bidirectional(a, b, peer:, domain_uuid:)
      done = Queue.new

      t1 = Thread.new do
        copy_stream(a, b) { |bytes| increment_client_bytes(a, :rx_bytes, bytes) }
      rescue StandardError => e
        done << e
      ensure
        done << :eof
      end

      t2 = Thread.new do
        copy_stream(b, a) { |bytes| increment_client_bytes(a, :tx_bytes, bytes) }
      rescue StandardError => e
        done << e
      ensure
        done << :eof
      end

      msg = done.pop
      log(:info, "proxy end peer=#{peer} uuid=#{domain_uuid} reason=#{msg.is_a?(Symbol) ? msg : msg.class}")
    ensure
      begin
        a.close unless a.closed?
      rescue StandardError
        # pass
      end
      begin
        b.close unless b.closed?
      rescue StandardError
        # pass
      end

      begin
        t1&.kill
        t2&.kill
      rescue StandardError
        # pass
      end
    end

    def copy_stream(src, dst)
      buf = +''
      loop do
        buf = src.readpartial(32 * 1024, buf)
        dst.write(buf)
        yield(buf.bytesize) if block_given?
      end
    end

    # ---- Helpers ----

    def safe_peer(sock)
      addr = sock.peeraddr
      "#{addr[3]}:#{addr[1]}"
    rescue StandardError
      'unknown'
    end

    def increment_client_bytes(sock, key, bytes)
      @clients_mutex.synchronize do
        info = @clients[sock]
        info[key] += bytes if info
      end
    end

    def update_client_domain(sock, domain_uuid)
      @clients_mutex.synchronize do
        info = @clients[sock]
        return unless info

        info.domain_uuid = domain_uuid
        info.domain_name = domain_name_for(domain_uuid)
      end
    end

    def domain_name_for(domain_uuid)
      lv = LibvirtClient.new
      dom = lv.lookup_domain_by_uuid(domain_uuid)
      dom&.name
    rescue StandardError => e
      log(:warn, "failed to get domain name for #{domain_uuid}: #{e.class}: #{e.message}")
      nil
    end
  end
end
