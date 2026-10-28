# rubocop:disable Naming/FileName
# Nix's Git-gem installer does not forward the Gemfile's recursive glob.
require 'bundler'

module HaveAPIGitGemspecGlob
  GEM_NAMES = %w[haveapi haveapi-client haveapi-go-client haveapi-rust-client haveapi-typescript-client].freeze

  def initialize(options)
    if GEM_NAMES.include?(options['name']) && !options.has_key?('glob')
      super(options.merge('glob' => '**/*.gemspec'))
    else
      super
    end
  end
end

Bundler::Source::Git.prepend(HaveAPIGitGemspecGlob)

# rubocop:enable Naming/FileName
