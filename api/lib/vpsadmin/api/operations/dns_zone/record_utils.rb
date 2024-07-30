module VpsAdmin::API
  module Operations::DnsZone::RecordUtils
    def process_record(attrs, record_type: nil)
      return attrs unless attrs[:content]

      record_type ||= attrs[:record_type]
      ret = attrs.clone

      ret[:content].strip!

      # Parse MX
      if record_type == 'MX' && /\A(\d+)\s+([^$]+)\z/ =~ ret[:content]
        ret[:priority] = Regexp.last_match(1).to_i
        ret[:content] = Regexp.last_match(2)
      end

      # Ensure domains are FQDNs
      if %w[CNAME MX NS PTR SRV].include?(record_type) && !ret[:content].end_with?('.')
        ret[:content] << '.'
      end

      ret
    end
  end
end
