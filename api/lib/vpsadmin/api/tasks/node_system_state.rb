module VpsAdmin::API::Tasks
  class NodeSystemState < Base
    def reconstruct
      total = 0

      ::Node.where(role: %i[node storage]).find_each do |node|
        count = VpsAdmin::API::Operations::Node::ReconstructSystemStates.run(node)
        puts "#{node.domain_name}: reconstructed #{count} system states"
        total += count
      end

      puts "Reconstructed #{total} system states in total"
    end
  end
end
