# frozen_string_literal: true

require 'spec_helper'
require 'optparse'

RSpec.describe VpsAdmin::CLI::Commands::BackupDataset do
  def parse_options(*args)
    command = described_class.allocate
    parser = OptionParser.new { |opts| command.options(opts) }

    parser.parse!(args)

    command.instance_variable_get(:@opts)
  end

  it 'accepts the corrected retry attempts option spelling' do
    expect(parse_options('--retry-attempts', '3')[:attempts]).to eq(3)
  end

  it 'keeps the historical misspelled retry attempts option as an alias' do
    expect(parse_options('--retry-attemps', '4')[:attempts]).to eq(4)
  end
end
