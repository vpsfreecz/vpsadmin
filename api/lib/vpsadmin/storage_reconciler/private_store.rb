require 'fileutils'
require 'openssl'
require 'securerandom'

module VpsAdmin
  module StorageReconciler
    # The caller owns the directory. Only completed files are published by name.
    class PrivateStore
      class Invalid < StandardError; end

      KEY_NAME = 'finding-key.bin'.freeze
      KEY_BYTES = 32
      KEY_VERSION = 1

      attr_reader :root, :run_id, :key_id

      def initialize(root:, run_id:, create: false)
        raise Invalid, 'private directory must be absolute' unless File.absolute_path(root) == root
        raise Invalid, 'run ID must be positive' unless run_id.to_i > 0

        @root = root
        @run_id = run_id.to_i
        reject_symlink_ancestors!(root)
        check_directory!(root, create:)
        @key = load_key!(create:)
        @key_id = Digest::SHA256.hexdigest(@key)[0, 32]
        check_directory!(run_directory, create:)
      end

      def run_directory
        File.join(root, "run-#{run_id}")
      end

      def path(name)
        raise Invalid, 'invalid artifact name' unless name.match?(/\A[a-z][a-z0-9_-]*\.(json|jsonl)\z/)

        File.join(run_directory, name)
      end

      def write(name)
        final_path = path(name)
        raise Invalid, 'artifact already exists' if File.exist?(final_path)

        temporary = File.join(run_directory, ".#{name}.#{SecureRandom.hex(12)}.tmp")
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.chmod(0o600)
          yield file
          file.flush
          file.fsync
          file.close
          File.link(temporary, final_path)
          File.unlink(temporary)
          sync_directory!
        end
        final_path
      ensure
        FileUtils.rm_f(temporary) if temporary
      end

      def each_line(name, &)
        File.open(path(name), File::RDONLY | File::NOFOLLOW) do |file|
          raise Invalid, 'artifact has unsafe ownership or permissions' unless
            file.stat.file? && file.stat.uid == Process.uid &&
            file.stat.mode & 0o777 == 0o600

          file.each_line(&)
        end
      end

      def read_json(name)
        data = nil
        each_line(name) do |line|
          raise Invalid, 'JSON artifact has multiple lines' if data

          data = JSON.parse(line)
        end
        raise Invalid, 'empty JSON artifact' unless data

        data
      rescue JSON::ParserError
        raise Invalid, 'malformed JSON artifact'
      end

      def sync_directory!
        File.open(run_directory, File::RDONLY | File::NOFOLLOW, &:fsync)
      end

      def key_metadata
        { 'algorithm' => 'HMAC-SHA256', 'canonicalization_version' => KEY_VERSION,
          'key_id' => key_id }
      end

      def check_key_metadata!(metadata)
        raise Invalid, 'finding key metadata mismatch' unless metadata == key_metadata
      end

      def opaque_disk_key(node_id:, zpool:, path:, type:, guid:)
        payload = {
          'version' => KEY_VERSION, 'node_id' => node_id.to_s, 'zpool' => zpool,
          'path' => path, 'type' => type, 'guid' => guid.to_s
        }
        hmac(payload)
      end

      def opaque_edge_key(node_id:, zpool:, source:, source_type:, source_guid:,
                          clone:, clone_type:, clone_guid:)
        hmac({
          'version' => KEY_VERSION, 'node_id' => node_id.to_s, 'zpool' => zpool,
          'source' => { 'path' => source, 'type' => source_type, 'guid' => source_guid.to_s },
          'clone' => { 'path' => clone, 'type' => clone_type, 'guid' => clone_guid.to_s }
        })
      end

      def hmac(payload)
        OpenSSL::HMAC.hexdigest('SHA256', @key, Format.canonical(payload))
      end

      private

      def load_key!(create:)
        key_path = File.join(root, KEY_NAME)
        if File.exist?(key_path) || File.symlink?(key_path)
          stat = File.lstat(key_path)
          raise Invalid, 'finding key is a symlink' if stat.symlink?
          raise Invalid, 'finding key has unsafe ownership or permissions' unless
            stat.file? && stat.uid == Process.uid && stat.mode & 0o777 == 0o600

          key = File.open(key_path, File::RDONLY | File::NOFOLLOW, &:read)
          raise Invalid, 'finding key has invalid length' unless key.bytesize == KEY_BYTES

          return key
        end
        raise Invalid, 'finding key is missing' unless create && Dir.empty?(root)

        key = SecureRandom.random_bytes(KEY_BYTES)
        File.open(key_path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.write(key)
          file.flush
          file.fsync
        end
        File.open(root, File::RDONLY | File::NOFOLLOW, &:fsync)
        key
      end

      def check_directory!(directory, create:)
        if File.exist?(directory) || File.symlink?(directory)
          stat = File.lstat(directory)
          raise Invalid, 'private directory is a symlink' if stat.symlink?
          raise Invalid, 'private directory is not owned by this user' unless stat.uid == Process.uid
          raise Invalid, 'private directory is not private' unless
            stat.directory? && stat.mode & 0o777 == 0o700
        elsif create
          Dir.mkdir(directory, 0o700)
          File.chmod(0o700, directory)
          File.open(File.dirname(directory), File::RDONLY, &:fsync)
        else
          raise Invalid, 'private directory is missing'
        end
      end

      def reject_symlink_ancestors!(directory)
        current = '/'
        directory.split('/').reject(&:empty?).each do |part|
          current = File.join(current, part)
          next unless File.exist?(current) || File.symlink?(current)

          raise Invalid, 'private path contains a symlink' if File.lstat(current).symlink?
        end
      end
    end
  end
end
