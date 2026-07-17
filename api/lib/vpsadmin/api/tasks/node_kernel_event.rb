module VpsAdmin::API::Tasks
  class NodeKernelEvent < Base
    def reconstruct
      total = 0

      ::Node.where(role: %i[node storage]).find_each do |node|
        count = VpsAdmin::API::Operations::Node::ReconstructKernelEvents.run(node)
        puts "#{node.domain_name}: reconstructed #{count} kernel events"
        total += count
      end

      puts "Reconstructed #{total} kernel events in total"
    end
  end
end
