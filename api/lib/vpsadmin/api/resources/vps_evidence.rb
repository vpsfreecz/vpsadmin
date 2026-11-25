class VpsAdmin::API::Resources::VpsEvidence < HaveAPI::Resource
  include VpsAdmin::API::VpsEvidenceReadResource

  route 'vps_evidence'
  desc 'Read current VPS evidence credit greater than zero'

  class Index < HaveAPI::Action
    include VpsAdmin::API::VpsEvidenceReadAction

    desc 'List visible VPS and signal pairs with positive current credit, ordered by signal, descending credit and VPS ID'
    input do
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      resource VpsAdmin::API::Resources::Location
      resource VpsAdmin::API::Resources::Environment
      string :signal, choices: ::VpsEvidence::SIGNALS.keys, label: 'Evidence signal'
      integer :offset, default: 0, fill: true, number: { min: 0 }, label: 'Rows to skip', desc: 'Zero-based offset in the filtered positive-credit list.'
      integer :limit, default: 25, fill: true, number: { min: 1, max: 100 }, label: 'Rows per page', desc: 'Maximum number of rows returned, from 1 to 100.'
    end
    output(:object_list, namespace: :vps_evidence) { use :all }
    meta(:global) do
      output do
        integer :total_count, label: 'Total authorized positive rows', desc: 'Number of visible VPS and signal pairs with positive credit after filtering and before pagination.'
        integer :offset, label: 'Rows to skip', desc: 'Zero-based offset in the filtered positive-credit list.'
        integer :limit, label: 'Rows per page', desc: 'Maximum number of rows returned, from 1 to 100.'
        integer :next_offset, nullable: true, label: 'Next page offset', desc: 'Offset for the next page, or null on the final page.'
      end
    end

    authorize do |user|
      unless user.role == :admin
        input blacklist: %i[user]
        output blacklist: %i[user node]
      end
      allow
    end

    def exec
      filters = %i[vps user node location environment].to_h { |key| [:"#{key}_id", input[key]&.id] }
      evidence_result(read_projection.positive(**filters, **input.except(:vps, :user, :node, :location, :environment)))
    rescue ArgumentError => e
      error!(e.message)
    end
  end
end
