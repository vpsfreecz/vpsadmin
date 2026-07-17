module VpsAdmin::API::Resources
  class NodeSoftwareVersion < HaveAPI::Resource
    model ::NodeSoftwareVersion
    desc 'Booted and currently activated Node software identities'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      string :generation, choices: ::NodeSoftwareVersion.generations.keys
      string :component, choices: ::NodeSoftwareVersion.components.keys
      string :version, nullable: true
      string :version_source, choices: ::NodeSoftwareVersion.version_sources.keys, nullable: true
      string :revision, nullable: true
      string :revision_source, choices: ::NodeSoftwareVersion.revision_sources.keys, nullable: true
      bool :revision_dirty
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input do
        string :generation, choices: ::NodeSoftwareVersion.generations.keys
        string :component, choices: ::NodeSoftwareVersion.components.keys
        string :version
        string :version_source, choices: ::NodeSoftwareVersion.version_sources.keys
        string :revision
        string :revision_source, choices: ::NodeSoftwareVersion.revision_sources.keys
        bool :revision_dirty
      end
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeSoftwareVersion.all,
          input
        )
        scope = scope.where(generation: input[:generation]) if input[:generation]
        scope = scope.where(component: input[:component]) if input[:component]
        scope = scope.where(version: input[:version]) if input[:version]
        scope = scope.where(version_source: input[:version_source]) if input[:version_source]
        scope = scope.where(revision: input[:revision]) if input[:revision]
        scope = scope.where(revision_source: input[:revision_source]) if input[:revision_source]
        scope = scope.where(revision_dirty: input[:revision_dirty]) if input.has_key?(:revision_dirty)
        scope.order(:id)
      end
    end
  end
end
