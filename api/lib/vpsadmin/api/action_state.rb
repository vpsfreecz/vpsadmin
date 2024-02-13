module VpsAdmin::API
  class ActionState < HaveAPI::ActionState
    def self.list_pending(user, offset, limit, order)
      ret = []
      return ret if user.nil?

      q = ::TransactionChain.where(
        user: user,
        state: [
          ::TransactionChain.states[:queued],
          ::TransactionChain.states[:rollbacking]
        ]
      ).order(
        "id #{order == :newest ? 'DESC' : 'ASC'}"
      ).offset(offset).limit(limit).each do |chain|
        ret << new(user, state: chain)
      end

      ret
    end

    def initialize(user, id: nil, state: nil)
      return if user.nil?

      @chain = state || ::TransactionChain.find_by(
        id: id,
        user: user
      )
    end

    def valid?
      !@chain.nil?
    end

    def finished?
      %w[done failed fatal resolved].include?(@chain.state)
    end

    def status
      %w[queued done].include?(@chain.state)
    end

    def id
      @chain.id
    end

    def label
      @chain.label
    end

    def progress
      { current: @chain.progress, total: @chain.size, unit: 'transactions' }
    end

    def created_at
      @chain.created_at
    end

    def updated_at
      @chain.created_at
    end
  end
end
