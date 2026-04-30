# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Utils::Dns do
  def original_get_ptr
    method = described_class.instance_method(:get_ptr)
    method = method.super_method until method.owner == described_class
    method
  end

  subject(:helper) do
    get_ptr_method = original_get_ptr

    Class.new do
      define_method(:get_ptr) do |ip|
        get_ptr_method.bind_call(self, ip)
      end
    end.new
  end

  it 'returns the PTR hostname from Resolv' do
    resolver = instance_double(Resolv)

    allow(Resolv).to receive(:new).and_return(resolver)
    allow(resolver).to receive(:getname).with('192.0.2.10').and_return('ptr.example.test')

    expect(helper.get_ptr('192.0.2.10')).to eq('ptr.example.test')
  end

  it 'returns resolver errors as strings' do
    resolver = instance_double(Resolv)

    allow(Resolv).to receive(:new).and_return(resolver)
    allow(resolver).to receive(:getname).with('192.0.2.10')
                                        .and_raise(Resolv::ResolvError, 'no name')

    expect(helper.get_ptr('192.0.2.10')).to eq('no name')
  end
end
