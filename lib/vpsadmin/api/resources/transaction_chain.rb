class VpsAdmin::API::Resources::TransactionChain < HaveAPI::Resource
  model ::TransactionChain
  desc 'Access transaction chains'

  params(:all) do
    id :id, label: 'Chain ID'
    string :name, label: 'Name', desc: 'For internal use only'
    string :label, label: 'Label', desc: 'Human-friendly name'
    string :state, label: 'State', choices: ::TransactionChain.states.keys
    integer :size, label: 'Size', desc: 'Number of transactions in the chain'
    integer :progress, label: 'Progress', desc: 'How many transactions are finished'
    resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
    datetime :created_at, label: 'Creation date'
    custom :concerns, db_name: :format_concerns
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List transaction chains'

    input do
      string :name, label: 'Name', desc: 'For internal use only'
      string :state, label: 'State', choices: ::TransactionChain.states.keys
      resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
      resource VpsAdmin::API::Resources::UserSession, label: 'User session'
      string :class_name, label: 'Class name', desc: 'Search by concerned class name'
      integer :row_id, label: 'Row id', desc: 'Search by concerned row id'
      
      patch :limit, default: 25, fill: true
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      input blacklist: %i(user)
      output blacklist: %i(user)
      allow
    end

    def query
      q = ::TransactionChain.where(with_restricted)

      q = q.where(name: input[:name]) if input[:name]
      q = q.where(state: ::TransactionChain.states[input[:state]]) if input[:state]
      q = q.where(user: input[:user]) if input[:user]
      q = q.where(user_session: input[:user_session]) if input[:user_session]
      q = q.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: {class_name: input[:class_name]}
      ) if input[:class_name]
      q = q.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: {row_id: input[:row_id]}
      ) if input[:row_id]

      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query)
          .includes(:transaction_chain_concerns)
          .limit(input[:limit])
          .offset(input[:offset])
          .order('transaction_chains.created_at DESC, transaction_chains.id DESC')
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
