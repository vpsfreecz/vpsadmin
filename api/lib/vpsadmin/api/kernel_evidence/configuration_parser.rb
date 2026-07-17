module VpsAdmin::API::KernelEvidence
  class ConfigurationParser
    def self.call(content)
      content.each_line.with_object({}) do |raw_line, options|
        line = raw_line.chomp

        if (match = line.match(/\A(CONFIG_[A-Z0-9_]+)=(.*)\z/))
          options[match[1]] = match[2]
        elsif (match = line.match(/\A# (CONFIG_[A-Z0-9_]+) is not set\z/))
          options[match[1]] = 'n'
        end
      end
    end
  end
end
