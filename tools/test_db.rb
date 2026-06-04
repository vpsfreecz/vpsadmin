# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'
require 'socket'
require 'tmpdir'

module VpsAdmin
  module TestDb
    class Error < StandardError; end

    DEFAULT_DATABASE = 'vpsadmin_test'
    DEFAULT_ENCODING = 'utf8mb3'
    DEFAULT_COLLATION = 'utf8mb3_unicode_ci'
    DEFAULT_HOST = '127.0.0.1'
    DEFAULT_PASSWORD = 'root'
    DEFAULT_PORT = 13_306
    DEFAULT_USER = 'root'
    START_TIMEOUT = 30

    class Instance
      attr_reader :database, :host, :port, :state_dir

      def initialize(state_dir:, port:, database:)
        @state_dir = state_dir
        @port = port
        @database = database
        @host = DEFAULT_HOST
      end

      def start
        ensure_binaries!
        FileUtils.mkdir_p(state_dir)

        initialized = initialized?
        initialize_database! unless initialized

        unless pid_alive?
          remove_stale_runtime_files
          start_server!
        end

        wait_for_ready!
        configure_root! unless configured? && tcp_query('SELECT 1')
        ensure_database!
        write_metadata
      end

      def stop
        return false unless pid_alive?

        mariadb_admin('shutdown')
        wait_for_shutdown
        remove_stale_runtime_files
        true
      rescue Error
        kill_server
        wait_for_shutdown
        remove_stale_runtime_files
        true
      end

      def running?
        pid_alive? && tcp_query('SELECT 1')
      end

      def prune
        stop if pid_alive?
        FileUtils.rm_rf(state_dir)
      end

      def url(database_name = database)
        "mysql2://#{DEFAULT_USER}:#{DEFAULT_PASSWORD}@#{host}:#{port}/#{database_name}" \
          "?encoding=#{DEFAULT_ENCODING}&collation=#{DEFAULT_COLLATION}"
      end

      def client_args
        [
          binary('mariadb'),
          '--host', host,
          '--port', port.to_s,
          '--user', DEFAULT_USER
        ]
      end

      def client_env
        { 'MYSQL_PWD' => DEFAULT_PASSWORD }
      end

      private

      def data_dir
        File.join(state_dir, 'data')
      end

      def socket_path
        File.join(state_dir, 'mysql.sock')
      end

      def pid_path
        File.join(state_dir, 'mysql.pid')
      end

      def log_path
        File.join(state_dir, 'mysql.log')
      end

      def configured_path
        File.join(state_dir, 'configured')
      end

      def metadata_path
        File.join(state_dir, 'env')
      end

      def initialized?
        File.directory?(File.join(data_dir, 'mysql'))
      end

      def configured?
        File.exist?(configured_path)
      end

      def initialize_database!
        FileUtils.rm_rf(data_dir)
        run!(
          binary('mariadb-install-db'),
          '--no-defaults',
          "--datadir=#{data_dir}",
          '--auth-root-authentication-method=normal',
          '--skip-test-db'
        )
      end

      def start_server!
        FileUtils.touch(log_path)
        Process.spawn(
          binary('mariadbd'),
          '--no-defaults',
          "--datadir=#{data_dir}",
          "--socket=#{socket_path}",
          "--pid-file=#{pid_path}",
          "--port=#{port}",
          "--bind-address=#{host}",
          "--log-error=#{log_path}",
          '--skip-networking=0',
          out: [log_path, 'a'],
          err: %i[child out]
        ).tap { |pid| Process.detach(pid) }
      rescue SystemCallError => e
        raise Error, "Unable to start mariadbd: #{e.message}"
      end

      def wait_for_ready!
        deadline = Time.now + START_TIMEOUT

        until Time.now > deadline
          return if socket_query('SELECT 1') || (pid_alive? && tcp_query('SELECT 1'))

          sleep 0.25
        end

        raise Error, "MariaDB did not become ready within #{START_TIMEOUT}s\n#{log_tail}"
      end

      def configure_root!
        if socket_query(auth_sql)
          File.write(configured_path, "configured\n")
          return
        end

        if tcp_query('SELECT 1')
          File.write(configured_path, "configured\n")
          return
        end

        raise Error, "Unable to configure MariaDB root access\n#{log_tail}"
      end

      def ensure_database!
        tcp_query!(
          "CREATE DATABASE IF NOT EXISTS #{quote_identifier(database)} " \
          "CHARACTER SET #{DEFAULT_ENCODING} COLLATE #{DEFAULT_COLLATION}"
        )
      end

      def auth_sql
        <<~SQL
          ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';
          CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY 'root';
          GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
          FLUSH PRIVILEGES;
        SQL
      end

      def tcp_query(sql)
        query(sql, tcp: true).success?
      end

      def tcp_query!(sql)
        result = query(sql, tcp: true)
        return if result.success?

        raise Error, result.message
      end

      def socket_query(sql)
        query(sql, tcp: false).success?
      end

      def query(sql, tcp:)
        args = [binary('mariadb')]
        env = {}

        if tcp
          env['MYSQL_PWD'] = DEFAULT_PASSWORD
          args += ['--host', host, '--port', port.to_s, '--user', DEFAULT_USER]
        else
          args += ['--protocol=socket', "--socket=#{socket_path}", '--user', DEFAULT_USER]
        end

        args += ['--execute', sql]
        Result.capture(env, args)
      end

      def mariadb_admin(command)
        result = Result.capture(
          client_env,
          [
            binary('mariadb-admin'),
            '--host', host,
            '--port', port.to_s,
            '--user', DEFAULT_USER,
            command
          ]
        )
        return if result.success?

        raise Error, result.message
      end

      def wait_for_shutdown
        deadline = Time.now + 10

        while Time.now <= deadline
          return unless pid_alive?

          sleep 0.2
        end

        kill_server
      end

      def kill_server
        server_pid = pid
        return unless server_pid && process_alive?(server_pid)

        Process.kill('TERM', server_pid)
      rescue Errno::ESRCH
        nil
      end

      def pid_alive?
        server_pid = pid
        server_pid && process_alive?(server_pid)
      end

      def pid
        Integer(File.read(pid_path).strip)
      rescue Errno::ENOENT, ArgumentError
        nil
      end

      def process_alive?(process_id)
        Process.kill(0, process_id)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def remove_stale_runtime_files
        FileUtils.rm_f([pid_path, socket_path])
      end

      def write_metadata
        File.write(
          metadata_path,
          "DATABASE_URL=#{url}\nSTATE_DIR=#{state_dir}\n"
        )
      end

      def quote_identifier(value)
        "`#{value.to_s.gsub('`', '``')}`"
      end

      def log_tail
        return '' unless File.exist?(log_path)

        lines = File.readlines(log_path).last(20)
        return '' if lines.empty?

        "Last lines from #{log_path}:\n#{lines.join}"
      end

      def run!(*args)
        result = Result.capture({}, args)
        return if result.success?

        raise Error, result.message
      end

      def ensure_binaries!
        %w[mariadb mariadb-admin mariadb-install-db mariadbd].each do |name|
          binary(name)
        end
      end

      def binary(name)
        TestDb.binary(name)
      end
    end

    Result = Struct.new(:stdout, :stderr, :status) do
      def self.capture(env, args)
        stdout, stderr, status = Open3.capture3(env, *args)
        new(stdout: stdout, stderr: stderr, status: status)
      end

      def success?
        status.success?
      end

      def message
        detail = [stdout, stderr].map(&:strip).reject(&:empty?).join("\n")
        command = status.respond_to?(:pid) ? "command pid #{status.pid}" : 'command'
        return "#{command} failed" if detail.empty?

        "#{command} failed:\n#{detail}"
      end
    end

    module_function

    def auto_start!
      return @auto_instance.url if @auto_instance

      instance = Instance.new(
        state_dir: Dir.mktmpdir('vpsadmin-test-db-auto-'),
        port: free_port,
        database: database_name
      )
      instance.start

      @auto_instance = instance
      at_exit do
        instance.stop
      ensure
        instance.prune
      end

      warn "Started local MariaDB test database at #{instance.url}"
      instance.url
    end

    def manual_instance
      Instance.new(
        state_dir: manual_state_dir,
        port: manual_port,
        database: database_name
      )
    end

    def database_name
      env_value('VPSADMIN_TEST_DB_NAME', DEFAULT_DATABASE)
    end

    def manual_port
      env_integer('VPSADMIN_TEST_DB_PORT', DEFAULT_PORT)
    end

    def manual_state_dir
      ENV.fetch('VPSADMIN_TEST_DB_STATE_DIR') do
        File.join(runtime_root, "vpsadmin-test-db-#{repo_key}")
      end
    end

    def runtime_root
      ENV.fetch('XDG_RUNTIME_DIR', '/tmp')
    end

    def repo_root
      File.realpath(File.join(__dir__, '..'))
    end

    def repo_key
      Digest::SHA256.hexdigest(repo_root)[0, 12]
    end

    def binary(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, name)
        return path if File.executable?(path) && !File.directory?(path)
      end

      raise Error,
            "Missing #{name}; run this from nix develop .#api, " \
            '.#libnodectld, or .#vpsadmin'
    end

    def free_port
      TCPServer.open(DEFAULT_HOST, 0) { |server| server.addr[1] }
    end

    def env_value(name, default)
      value = ENV.fetch(name, '').strip
      value.empty? ? default : value
    end

    def env_integer(name, default)
      value = ENV.fetch(name, '').strip
      return default if value.empty?

      Integer(value)
    rescue ArgumentError
      raise Error, "#{name} must be an integer"
    end
  end
end
