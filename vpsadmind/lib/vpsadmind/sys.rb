require 'fiddle'
require 'fiddle/import'

module VpsAdmind
  class Sys
    module Int
      extend Fiddle::Importer
      dlload Fiddle.dlopen(nil)
      extern 'int chroot(const char *path)'
    end

    def chroot(path)
      ret = Int.chroot(path)
      raise SystemCallError, Fiddle.last_error if ret != 0
      ret
    end
  end
end
