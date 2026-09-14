module VpsAdmin::API::KernelEvidence
  module StableState
    module_function

    # Match the recorder's boot identity rule, but require a known identity
    # before treating an observation as positive historical evidence.
    def same_boot?(left, right)
      return false unless left && right

      if left.boot_id && right.boot_id
        left.boot_id == right.boot_id
      else
        left.booted_at && right.booted_at && left.booted_at == right.booted_at
      end
    end

    def complete?(report)
      return false unless report
      return false if report.livepatches.any? do |livepatch|
        [livepatch.loaded, livepatch.enabled, livepatch.transition].any?(&:nil?)
      end

      report.errors.none? do |error|
        error.component == 'livepatches' ||
          error.component.match?(/\Alivepatch\..+\.(?:enabled|transition)\z/)
      end
    end

    def transitioning?(livepatches)
      livepatches.any?(&:transition)
    end

    def effective_ids(livepatches)
      livepatches.select do |livepatch|
        livepatch.loaded && livepatch.enabled && livepatch.transition == false
      end.map(&:id).sort
    end

    def stable?(report)
      complete?(report) &&
        same_boot?(report.kernel, report.kernel) &&
        report.kernel.booted_release.is_a?(String) &&
        report.kernel.reported_release.is_a?(String) &&
        !transitioning?(report.livepatches)
    end

    def confirms?(baseline, observation)
      stable?(baseline) && stable?(observation) &&
        same_boot?(baseline.kernel, observation.kernel) &&
        baseline.kernel.reported_release == observation.kernel.reported_release &&
        effective_ids(baseline.livepatches) == effective_ids(observation.livepatches)
    end
  end
end
