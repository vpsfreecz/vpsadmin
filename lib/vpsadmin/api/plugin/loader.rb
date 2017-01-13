module VpsAdmin::API::Plugin
  class Loader
    def self.load
      plugin_dir = File.realpath(File.join(
          VpsAdmin::API.root,
          'plugins'
      ))
      return unless File.exists?(plugin_dir)

      dirs = %w(lib models resources)

      Dir.entries(plugin_dir).select do |v|
        v != '.' && v != '..' && File.directory?(File.join(plugin_dir, v))
      end.each do |p|
        Kernel.load(File.join(plugin_dir, p, 'meta.rb'))

        dirs.each do |d|
          path = File.join(plugin_dir, p, d)
          require_all(File.realpath(path)) if File.exists?(path)
        end
      end
    end
  end
end
