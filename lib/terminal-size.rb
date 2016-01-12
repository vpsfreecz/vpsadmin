class Terminal
  class Size; VERSION = '0.0.6' end
  class << self
    def size
      size_via_low_level_ioctl or size_via_stty or nil
    end
    def size!; size or _height_width_hash_from 25, 80 end

    # These are experimental
    def resize direction, magnitude
      tmux 'resize-pane', "-#{direction}", magnitude
    end

    def tmux *cmd
      system 'tmux', *(cmd.map &:to_s)
    end

    IOCTL_INPUT_BUF = "\x00"*8
    def size_via_low_level_ioctl
      # Thanks to runpaint for the general approach to this
      return unless $stdin.respond_to? :ioctl
      code = tiocgwinsz_value_for RUBY_PLATFORM
      return unless code
      buf = IOCTL_INPUT_BUF.dup
      return unless $stdout.ioctl(code, buf).zero?
      return if IOCTL_INPUT_BUF == buf
      got = buf.unpack('S4')[0..1]
      _height_width_hash_from *got
    rescue
      nil
    end

    def tiocgwinsz_value_for platform
      # This is as reported by <sys/ioctl.h>
      # Hard-coding because it seems like overkll to acutally involve C for this.
      {
        /linux/ => 0x5413,
        /darwin/ => 0x40087468, # thanks to brandon@brandon.io for the lookup!
      }.find{|k,v| platform[k]}
    end

    def size_via_stty
      ints = `stty size`.scan(/\d+/).map &:to_i
      _height_width_hash_from *ints
    rescue
      nil
    end

    private
    def _height_width_hash_from *dimensions
      { :height => dimensions[0], :width => dimensions[1] }
    end

  end
end
