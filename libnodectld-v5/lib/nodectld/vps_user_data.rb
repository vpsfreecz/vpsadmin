module NodeCtld
  module VpsUserData
    def self.for_format(format)
      case format
      when 'script'
        VpsUserData::Script
      when 'cloudinit_config', 'cloudinit_script'
        VpsUserData::CloudInit
      when 'nixos_configuration', 'nixos_flake_configuration', 'nixos_flake_uri'
        VpsUserData::Nixos
      end
    end
  end
end
