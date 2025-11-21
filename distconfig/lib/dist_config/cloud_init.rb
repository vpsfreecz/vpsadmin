module DistConfig
  module CloudInit
    def self.install_dnf
      'dnf install -y cloud-init'
    end

    def self.install_apkv2
      'apk add cloud-init'
    end

    def self.install_apkv3
      'apk add --no-interactive cloud-init'
    end

    def self.install_pacman
      'pacman -Sy --noconfirm cloud-init'
    end

    def self.install_apt
      'DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-init'
    end

    def self.install_zypper
      'zypper install -y cloud-init'
    end

    def self.install_emerge
      'emerge -q app-emulation/cloud-init'
    end

    def self.enable_systemd
      %w[
        cloud-config
        cloud-final
        cloud-init-local
        cloud-init-main
        cloud-init-network
        cloud-init
      ].map { |v| "systemctl enable #{v}.service || true" }.join("\n")
    end

    def self.enable_dinit
      %w[
        cloud-config
        cloud-final
        cloud-init
        cloud-init-local
      ].map { |v| "ln -s /usr/lib/dinit.d/#{v} /etc/dinit.d/boot.d/#{v}" }.join("\n")
    end

    def self.enable_alpine
      'setup-cloud-init'
    end

    def self.enable_gentoo(version)
      if version.start_with?('systemd-')
        enable_systemd
      else
        [
          'rc-update add cloud-init-local boot',
          'rc-update add cloud-config default',
          'rc-update add cloud-final default',
          'rc-update add cloud-init default'
        ].join("\n")
      end
    end
  end
end
