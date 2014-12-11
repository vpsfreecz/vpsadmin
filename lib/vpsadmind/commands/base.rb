module VpsAdmind::Commands
  class Base
    # Mapping of module names.
    MODULES = {
        :system => :System,
        :vz => :Vz,
        :zfs => :Zfs,
        :vps => :Vps
    }

    def self.handle(type)
      VpsAdmind::Command.register(self.to_s, type)
    end

    # Includes module from VpsAdmind::Utils using mapping
    # in Base::MODULES.
    def self.needs(*args)
      args.each do |arg|
        if arg.is_a?(Array)
          needs(arg)

        else
          send(:include, VpsAdmind::Utils.const_get(MODULES[arg]))
        end
      end
    end

    attr_accessor :output

    def initialize(cmd, params)
      @command = cmd

      params.each do |k,v|
        instance_variable_set(:"@#{k}", v)
      end

      @m_attr = Mutex.new
      @output = {}

      Thread.current[:command] = self
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

    def step=(str)
      attrs do
        @step = str
      end
    end

    def subtask
      attrs do
        @subtask
      end
    end

    def subtask=(pid)
      attrs do
        @subtask = pid
      end
    end

    protected
    def attrs
      ret = nil

      @m_attr.synchronize do
        ret = yield
      end

      ret
    end

    def ok
      {:ret => :ok}
    end
  end

  module DatasetTree ; end
  module Branch      ; end
  module Vps         ; end
  module Dataset     ; end
  module Shaper      ; end
  module Utils       ; end
end
