module VpsAdmin::API
  module HashOptions
    module Methods
      # @param opts [Hash]
      # @param defaults [Hash]
      def set_hash_opts(opts, defaults)
        ret = {}

        diff = opts.keys - defaults.keys

        fail "unknown options '#{diff.join(',')}'" unless diff.empty?

        defaults.each do |k, v|
          next if !opts.has_key?(k) && v.nil?

          ret[k] = opts[k].nil? ? v : opts[k]
        end

        ret
      end
    end

    def self.included(klass)
      klass.send(:extend, Methods)
      klass.send(:include, Methods)
    end
  end
end
