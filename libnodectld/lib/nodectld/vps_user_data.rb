module NodeCtld
  module VpsUserData
    def self.for_format(format)
      case format
      when 'script'
        VpsUserData::Script
      when 'cloudinit_config', 'cloudinit_script'
        VpsUserData::CloudInit
      end
    end
  end
end
