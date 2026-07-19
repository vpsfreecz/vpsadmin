module VpsAdmin::API::Tasks
  class NodeKernelEvent < Base
    def reconstruct
      NodeHistoryBackfill.new.reconstruct(components: [:kernel])
    end
  end
end
