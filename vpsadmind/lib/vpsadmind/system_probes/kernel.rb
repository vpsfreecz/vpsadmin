module VpsAdmind::SystemProbes
  class Kernel
    def version
      File.read('/proc/sys/kernel/osrelease').strip
    end
  end
end
