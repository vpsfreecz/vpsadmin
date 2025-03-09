module NodeCtld
  module VpsUserData
    def self.for_backend(backend)
      case backend
      when 'script'
        VpsUserData::Script
      when 'cloudinit'
        VpsUserData::CloudInit
      end
    end
  end
end
