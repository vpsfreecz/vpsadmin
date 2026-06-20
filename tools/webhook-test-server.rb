#!/usr/bin/env ruby
# Minimal HTTP server for manually testing vpsAdmin notification webhooks.

require 'fileutils'
require 'json'
require 'optparse'
require 'socket'
require 'time'

class WebhookTestServer
  DEFAULT_HEADERS = {
    'Content-Type' => 'text/plain',
    'X-VpsAdmin-Test-Server' => 'webhook-test-server'
  }.freeze

  def self.run(args)
    new(args).run
  end

  def initialize(args)
    @host = ENV.fetch('HOST', '127.0.0.1')
    @port = ENV.fetch('PORT', '18080').to_i
    @status = ENV.fetch('STATUS', '202').to_i
    @body = ENV.fetch('BODY', 'accepted')
    @log_dir = ENV.fetch('LOG_DIR', '/tmp/vpsadmin-webhook-test')
    @headers = DEFAULT_HEADERS.dup

    OptionParser.new do |opts|
      opts.banner = <<~BANNER
        Usage: #{$0} [options]

        Development services VM:
          #{$0} --host 127.0.0.1 --port 18080
          webhook URL: http://127.0.0.1:18080/events

        Host machine fallback:
          #{$0} --host 0.0.0.0 --port 18080
          webhook URL: http://<host-address>:18080/events
      BANNER

      opts.on('--host HOST', 'Bind address, default 127.0.0.1') { |v| @host = v }
      opts.on('--port PORT', Integer, 'Bind port, default 18080') { |v| @port = v }
      opts.on('--status STATUS', Integer, 'HTTP response status, default 202') { |v| @status = v }
      opts.on('--body BODY', 'HTTP response body, default accepted') { |v| @body = v }
      opts.on('--log-dir DIR', 'Request log directory') { |v| @log_dir = v }
      opts.on('--response-header HEADER', 'Response header as Name: value') do |v|
        name, value = v.split(':', 2)
        raise OptionParser::InvalidArgument, v unless name && value

        @headers[name.strip] = value.strip
      end
    end.parse!(args)
  end

  def run
    FileUtils.mkdir_p(@log_dir, mode: 0o700)
    @server = TCPServer.new(@host, @port)

    trap('INT') { stop }
    trap('TERM') { stop }

    warn "Listening on http://#{display_host}:#{@port}/events"
    warn "Writing requests to #{@log_dir}"

    loop do
      socket = @server.accept
      handle(socket)
    rescue IOError, Errno::EBADF
      break
    end
  ensure
    @server&.close
  end

  protected

  def stop
    @server&.close
  end

  def display_host
    @host == '0.0.0.0' ? '<host-address>' : @host
  end

  def handle(socket)
    request_line = socket.gets.to_s
    headers = read_headers(socket)
    body = read_body(socket, headers)
    parts = request_line.split(/\s+/, 3)
    timestamp = Time.now.utc.iso8601(6)

    payload = {
      timestamp:,
      remote_address: socket.peeraddr[3],
      method: parts[0],
      path: parts[1],
      protocol: parts[2].to_s.strip,
      headers:,
      body:
    }

    write_request(payload, timestamp)
    write_response(socket)

    warn "#{timestamp} #{payload.fetch(:method)} #{payload.fetch(:path)} -> #{@status}"
  ensure
    socket&.close
  end

  def read_headers(socket)
    headers = {}

    while (line = socket.gets)
      break if ["\r\n", "\n"].include?(line)

      name, value = line.split(':', 2)
      next unless name && value

      key = name.downcase
      headers[key] ||= []
      headers[key] << value.strip
    end

    headers
  end

  def read_body(socket, headers)
    length = Array(headers['content-length']).first.to_i
    length > 0 ? socket.read(length).to_s : ''
  end

  def write_request(payload, timestamp)
    path = File.join(@log_dir, "#{timestamp.gsub(/[^0-9]/, '')}.json")
    latest = File.join(@log_dir, 'request.json')
    json = JSON.pretty_generate(payload)

    File.write(path, json)
    File.write(latest, json)
  end

  def write_response(socket)
    response_headers = @headers.merge('Content-Length' => @body.bytesize.to_s)
    socket.write("HTTP/1.1 #{@status} #{reason_phrase}\r\n")
    response_headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("Connection: close\r\n\r\n")
    socket.write(@body)
  end

  def reason_phrase
    case @status
    when 200 then 'OK'
    when 201 then 'Created'
    when 202 then 'Accepted'
    when 400 then 'Bad Request'
    when 500 then 'Internal Server Error'
    else 'Response'
    end
  end
end

WebhookTestServer.run(ARGV)
