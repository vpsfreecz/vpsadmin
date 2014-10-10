class VpsAdmin::API::Resources::TransactionChain < HaveAPI::Resource
  version 1
  model ::TransactionChain
  desc 'Access transaction chains'

  params(:all) do
    id :id, label: 'Chain ID'
    string :name, label: 'Name', desc: 'For internal use only'
    string :label, label: 'Label', desc: 'Human-friendly name'
    string :state, label: 'State', choices: ::TransactionChain.states.values
    integer :size, label: 'Size', desc: 'Number of transactions in the chain'
    integer :progress, label: 'Progress', desc: 'How many transactions are finished'
    resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
    datetime :created_at, label: 'Creation date'
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List transaction chains'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      output blacklist: %i(user)
      allow
    end

    def exec
      ::TransactionChain.where(with_restricted).limit(input[:limit]).offset(input[:offset]).order('created_at DESC')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show transaction chain'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      output blacklist: %i(user)
      allow
    end

    def prepare
      @chain = ::TransactionChain.find_by!(with_restricted(id: params[:transaction_chain_id]))
    end

    def exec
      @chain
    end
  end
end
