class VpsAdmin::API::Resources::VPS::Evidence < HaveAPI::Resource
  include VpsAdmin::API::VpsEvidenceReadResource

  route '{vps_id}/evidence'
  desc 'Read current evidence credit for a VPS'

  class Index < HaveAPI::Action
    include VpsAdmin::API::VpsEvidenceReadAction

    desc 'List every supported evidence signal for this VPS, including zero recorded credit and unavailable values'
    output(:object_list, namespace: :evidence) { use :all }

    def prepare
      scope = ::Vps.including_deleted
      scope = scope.where(user_id: current_user.id) unless current_user.role == :admin
      @vps = scope.find(path_params['vps_id'])
    end

    def exec
      evidence_result(read_projection.for_vps(@vps.id))
    end
  end
end
