# frozen_string_literal: true

module NodeCtld
  module ContainerState
    module_function

    def normalize(attrs)
      ret = attrs.dup

      if ret.has_key?(:runtime_state)
        ret.delete(:state)
        ret[:config_state_error] ||= nil
        ret[:runtime_state_error] ||= nil
        return ret
      end

      legacy_state = ret.delete(:state)&.to_s

      case legacy_state
      when 'staged'
        ret[:config_state] = 'staged'
        ret[:runtime_state] = 'unknown'

      when 'error'
        ret[:config_state] = 'error'
        ret[:config_state_error] = {
          source: 'legacy_state',
          message: 'legacy osctld reported an undifferentiated error state'
        }
        ret[:runtime_state] = 'unknown'

      else
        ret[:config_state] = 'ready'
        ret[:runtime_state] = legacy_state || 'unknown'
      end

      ret[:config_state_error] ||= nil
      ret[:runtime_state_error] ||= nil
      ret
    end
  end
end
