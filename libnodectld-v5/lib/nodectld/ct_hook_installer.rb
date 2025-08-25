module NodeCtld
  class CtHookInstaller
    # @param pool_fs [String]
    # @param vps_id [Integer]
    def initialize(pool_fs, vps_id)
      @pool_fs = pool_fs
      @vps_id = vps_id
    end

    # @param hooks [Array<String>]
    def install_hooks(hooks)
      hooks.each do |hook|
        dst = hook_path(hook)

        FileUtils.cp(
          File.join(NodeCtld.root, 'templates', 'ct', 'hook', hook),
          "#{dst}.new"
        )

        File.chmod(0o500, "#{dst}.new")
        File.rename("#{dst}.new", dst)
      end

      nil
    end

    # @param hooks [Array<String>]
    def uninstall_hooks(hooks)
      hooks.each do |hook|
        FileUtils.rm_f(hook_path(hook))
      end

      nil
    end

    protected

    def hook_path(name)
      File.join(hook_dir, name)
    end

    def hook_dir
      File.join('/', @pool_fs, '..', 'hook/ct', @vps_id.to_s)
    end
  end
end
