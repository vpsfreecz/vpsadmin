module NodeCtl
  module Command
    # @param name [Symbol]
    # @param klass [Class]
    def self.register(name, klass)
      @commands ||= {}
      @commands[name] = klass
    end

    # @return [Array<Class>]
    def self.all
      @commands.values
    end

    # @param cmd [Symbol]
    # @return [Class]
    def self.get(cmd)
      @commands[cmd]
    end
  end
end
