class ValidationError < StandardError
  def initialize(msg)
    @msg = msg
  end

  def message
    @msg
  end
end

module Commands
end

class Command
  @@sorted_cmds = []

  def initialize
    @opts = {}
    @global_opts = {}
  end

  def options(opts, args)

  end

  def validate

  end

  def prepare

  end

  def post_send

  end

  def process

  end

  def set_global_options(opts)
    @global_opts = opts
  end

  def set_args(args)
    @args = args
  end

  def response(data)
    @res = data
  end

  def cmd
    self.class.cmd
  end

  def vpsadmind(d)
    @vpsadmind = d
  end

  def self.all
    if @@sorted_cmds.empty?
      cmds = {}

      Commands.constants.select do |c|
        obj = Commands.const_get(c)

        cmds[obj.cmd] = obj if obj.is_a?(Class)
      end

      tmp = cmds.sort do |a, b|
        a[0] <=> b[0]
      end

      tmp.each do|c|
        @@sorted_cmds << c[1]
      end
    end

    if block_given?
      @@sorted_cmds.each do |c|
        yield c
      end
    else
      @@sorted_cmds
    end
  end

  def self.get(cmd)
    self.all do |c|
      return c if c.cmd == cmd
    end

    nil
  end

  class << self
    @description = ''
    @args = ''
    @cmd = nil

    def description(desc = nil)
      if desc
        @description = desc
      else
        @description
      end
    end

    def args(text = nil)
      if text
        @args = text
      else
        @args
      end
    end

    def cmd(n = nil)
      if(n)
        @cmd = n
      elsif @cmd
        @cmd
      else
        name.split('::').last.downcase
      end
    end

    def label
      "#{cmd} #{args}"
    end

    def inherited(subclass)
      subclass.args(@args)
    end
  end
end

Dir[File.dirname(__FILE__) + '/command_templates/*.rb'].each {|file| require file }
Dir[File.dirname(__FILE__) + '/commands/*.rb'].each {|file| require file }
