# frozen_string_literal: true

module NodeCtldSpec
  module TestHandles
    OK = 999_001
    WARNING = 999_002
    FAIL_EXEC = 999_003
    FAIL_ROLLBACK = 999_004
    RAISE_GENERIC = 999_005
    NOT_IMPLEMENTED = 999_006
    HOOKS_PROBE = 999_007
    INVALID_RETURN = 999_008
  end

  module TestHandlers
    class Ok < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::OK

      def exec
        output[:handler] = 'ok'
        ok
      end

      def rollback
        output[:handler] = 'ok-rollback'
        ok
      end
    end

    class Warning < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::WARNING

      def exec
        output[:handler] = 'warning'
        { ret: :warning }
      end

      def rollback
        ok
      end
    end

    class FailExec < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::FAIL_EXEC

      def exec
        raise NodeCtld::SystemCommandFailed.new('spec-fail-exec', 23, 'exec failed')
      end

      def rollback
        output[:rolled_back] = true
        ok
      end
    end

    class FailRollback < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::FAIL_ROLLBACK

      def exec
        ok
      end

      def rollback
        raise NodeCtld::SystemCommandFailed.new('spec-fail-rollback', 42, 'rollback failed')
      end
    end

    class RaiseGeneric < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::RAISE_GENERIC

      def exec
        raise 'generic failure from spec handler'
      end

      def rollback
        ok
      end
    end

    class NotImplemented < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::NOT_IMPLEMENTED

      def exec
        raise NodeCtld::CommandNotImplemented
      end

      def rollback
        raise NodeCtld::CommandNotImplemented
      end
    end

    class HooksProbe < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::HOOKS_PROBE

      def exec
        output[:exec] = true
        ok
      end

      def rollback
        ok
      end

      def on_save(_db)
        Thread.current[:spec_on_save_calls] =
          Thread.current[:spec_on_save_calls].to_i + 1
      end

      def post_save
        Thread.current[:spec_post_save_calls] =
          Thread.current[:spec_post_save_calls].to_i + 1
      end
    end

    class InvalidReturn < NodeCtld::Commands::Base
      handle NodeCtldSpec::TestHandles::INVALID_RETURN

      def exec
        'not-a-valid-return-value'
      end

      def rollback
        ok
      end
    end
  end
end
