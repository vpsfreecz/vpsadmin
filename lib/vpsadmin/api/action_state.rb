module VpsAdmin::API
  class ActionState < HaveAPI::ActionState
    def self.list_pending(user, offset, limit)
      ret = []
      return ret if user.nil?

      ::TransactionChain.where(
          user: user,
          state: [
              ::TransactionChain.states[:queued],
              ::TransactionChain.states[:rollbacking],
          ]
      ).order('id DESC').offset(offset).limit(limit).each do |chain|
        ret << new(user, state: chain)
      end

      ret
    end

    def initialize(user, id: nil, state: nil)
      return if user.nil?

      if state
        @chain = state

      else
        @chain = ::TransactionChain.find_by(
          id: id,
          user: user,
        )
      end
    end

    def valid?
      !@chain.nil?
    end

    def finished?
      %w(done failed fatal resolved).include?(@chain.state)
    end

    def status
      %w(queued done).include?(@chain.state)
    end

    def id
      @chain.id
    end

    def label
      @chain.label
    end

    def progress
      {current: @chain.progress, total: @chain.size, unit: 'transactions'}
    end
  end
end
