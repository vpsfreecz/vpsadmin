# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gem::Specification do
  let(:specification) { described_class.load('vpsadmin-client.gemspec') }

  it 'declares directly required runtime dependencies' do
    dependency_names = specification.runtime_dependencies.map(&:name)

    expect(dependency_names).to include('ruby-progressbar')
  end
end
