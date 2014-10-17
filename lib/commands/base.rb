module VpsAdmind::Commands
  class Base
    def self.handle(type)
      Command.register(self.to_s, type)
    end

    attr_accessor :output

    def initialize(params)
      params.each do |k,v|
        instance_variable_set(:"@#{k}", v)
      end

      @m_attr = Mutex.new
      @output = {}
    end

    def exec

    end

    def rollback

    end

    def test

    end

    def post_save(db)

    end

    def step
      attrs do
        @step
      end
    end

    def subtask
      attrs do
        @subtask
      end
    end

    protected
    def ok
      {:ret => :ok}
    end
  end

  module Vps

  end

  module Dataset

  end
end
