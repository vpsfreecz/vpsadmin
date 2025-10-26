module DistConfig
  class Hostname
    attr_reader :local, :domain, :fqdn

    # @param fqdn [String]
    def initialize(fqdn)
      names = fqdn.split('.')
      @local = names.first
      @domain = names[1..].join('.')
      @fqdn = fqdn
    end

    alias to_s fqdn
  end
end
