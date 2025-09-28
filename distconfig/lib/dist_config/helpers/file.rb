require 'securerandom'

module DistConfig
  module Helpers::File
    def regenerate_file(path, mode)
      replacement = "#{path}.new-#{SecureRandom.hex(3)}"

      File.open(replacement, 'w', mode) do |new|
        if File.exist?(path)
          File.open(path, 'r') do |old|
            yield(new, old)
          end

        else
          yield(new, nil)
        end
      end

      File.rename(replacement, path)
    end

    def unlink_if_exists(path)
      File.unlink(path)
      true
    rescue Errno::ENOENT
      false
    end
  end
end
