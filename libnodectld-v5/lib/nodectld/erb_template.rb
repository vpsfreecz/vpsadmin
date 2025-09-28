require 'erb'
require 'fileutils'

module NodeCtld
  class ErbTemplate
    def self.render(name, vars)
      t = new(name, vars)
      t.render
    end

    def self.render_to(name, vars, path, perm: 0o644)
      File.write("#{path}.new", render(name, vars), perm:)
      File.rename("#{path}.new", path)
    end

    def self.render_to_if_changed(name, vars, path, perm: 0o644)
      tmp_path = "#{path}.new"
      File.write(tmp_path, render(name, vars), perm:)

      if !File.exist?(path) || !FileUtils.identical?(path, tmp_path)
        File.rename(tmp_path, path)

      else
        File.unlink(tmp_path)
        File.chmod(perm, path)
      end
    end

    def initialize(name, vars)
      @_tpl = ERB.new(
        File.read(File.join(File.dirname(__FILE__), '../../templates', "#{name}.erb")),
        trim_mode: '-'
      )

      vars.each do |k, v|
        if v.is_a?(Proc)
          define_singleton_method(k, &v)
        elsif v.is_a?(Method)
          define_singleton_method(k) { |*args, **kwargs| v.call(*args, **kwargs) }
        else
          define_singleton_method(k) { v }
        end
      end
    end

    def render
      @_tpl.result(binding)
    end
  end
end
