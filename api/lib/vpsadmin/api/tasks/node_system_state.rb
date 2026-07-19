module VpsAdmin::API::Tasks
  class NodeSystemState < Base
    def reconstruct
      NodeHistoryBackfill.new.reconstruct(components: [:system])
    end
  end
end
