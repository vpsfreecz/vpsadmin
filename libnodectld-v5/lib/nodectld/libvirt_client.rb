require 'libvirt'

module NodeCtld
  module LibvirtClient
    # @return [::Libvirt::Connect]
    def self.new
      ::Libvirt.open($CFG.get(:libvirt, :uri))
    end
  end
end
