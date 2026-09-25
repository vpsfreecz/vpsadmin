require 'digest'
require 'json'
require 'bigdecimal'

module VpsAdmin
  module StorageReconciler
    module Format
      VERSION = 1
      POLICY_VERSION = 1
      PLAN_POLICY_VERSION = 2
      PROTOCOL_VERSION = 1
      MAX_RECORD_BYTES = 64 * 1024

      class Invalid < StandardError; end

      module_function

      def canonical(value)
        JSON.generate(sort(value))
      end

      def digest(value)
        Digest::SHA256.hexdigest(canonical(value))
      end

      def record(kind, fields)
        data = { 'kind' => kind, 'version' => VERSION, 'fields' => sort(fields) }
        data['digest'] = digest(data)
        data
      end

      def verify_record!(record, expected_kind: nil)
        raise Invalid, 'record is not an object' unless record.is_a?(Hash)
        raise Invalid, 'unsupported record version' unless record['version'] == VERSION
        raise Invalid, 'unexpected record kind' if expected_kind && record['kind'] != expected_kind
        raise Invalid, 'record fields are missing' unless record['fields'].is_a?(Hash)

        actual = record['digest']
        unsigned = record.except('digest')
        raise Invalid, 'record digest mismatch' unless actual == digest(unsigned)

        record
      end

      def parse_line!(line, expected_kind: nil)
        raise Invalid, 'oversize record' if line.bytesize > MAX_RECORD_BYTES
        raise Invalid, 'record is not newline terminated' unless line.end_with?("\n")

        verify_record!(JSON.parse(line), expected_kind:)
      rescue JSON::ParserError
        raise Invalid, 'malformed JSON record'
      end

      def sort(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), ret| ret[key.to_s] = sort(entry) }
               .sort.to_h
        when Array
          value.map { |entry| sort(entry) }
        when BigDecimal
          value.to_s('F')
        else
          value
        end
      end
    end
  end
end
