# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Mail do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  describe '#daily_report' do
    it 'picks language from VPSADMIN_LANG and fires DailyReport' do
      allow(TransactionChains::Mail::DailyReport).to receive(:fire)

      with_env('VPSADMIN_LANG' => 'en') do
        task.daily_report
      end

      expect(TransactionChains::Mail::DailyReport).to have_received(:fire).with(SpecSeed.language)
    end
  end

  describe '#process' do
    let(:mailbox) { create_mailbox_fixture! }
    let(:message) { instance_double(Mail::Message, subject: 'Spec message') }

    it 'uses Mail::IMAP#all in dry-run mode' do
      mailbox
      retriever = instance_double(Mail::IMAP, all: [message])
      allow(::Mail::IMAP).to receive(:new).and_return(retriever)

      expect do
        task.process
      end.to output(/Dry run: received messages are not removed/).to_stderr

      expect(retriever).to have_received(:all).with(mailbox: 'INBOX')
      expect(retriever).to have_received(:all).with(mailbox: 'Junk')
    end

    it 'uses Mail::IMAP#find_and_delete in execute mode' do
      mailbox
      retriever = instance_double(Mail::IMAP, find_and_delete: [message])
      allow(::Mail::IMAP).to receive(:new).and_return(retriever)

      with_env('EXECUTE' => 'yes') do
        task.process
      end

      expect(retriever).to have_received(:find_and_delete).with(mailbox: 'INBOX', count: 10)
      expect(retriever).to have_received(:find_and_delete).with(mailbox: 'Junk', count: 10)
    end
  end

  describe 'handler iteration semantics' do
    let(:mailbox) { create_mailbox_fixture! }
    let(:message) { instance_double(Mail::Message) }

    def define_handler(name, calls, value)
      stub_const(name, Class.new do
        define_method(:initialize) { |mailbox| @mailbox = mailbox }
        define_method(:handle_message) do |_msg, dry_run:|
          raise 'dry-run flag missing' if dry_run.nil?

          calls << name
          value
        end
      end)
    end

    it 'treats false as ignored' do
      calls = []
      define_handler('SpecMailboxHandlerFalse', calls, false)
      create_mailbox_handler_fixture!(mailbox:, class_name: 'SpecMailboxHandlerFalse')

      ret = task.send(:handle_message, mailbox, message, dry_run: true)

      expect(ret).to be(false)
      expect(calls).to eq(['SpecMailboxHandlerFalse'])
    end

    it 'continues when a handler returns :continue' do
      calls = []
      define_handler('SpecMailboxHandlerContinue', calls, :continue)
      define_handler('SpecMailboxHandlerTruthy', calls, true)
      create_mailbox_handler_fixture!(
        mailbox:,
        class_name: 'SpecMailboxHandlerContinue',
        order: 1
      )
      create_mailbox_handler_fixture!(
        mailbox:,
        class_name: 'SpecMailboxHandlerTruthy',
        order: 2
      )

      ret = task.send(:handle_message, mailbox, message, dry_run: true)

      expect(ret).to be(true)
      expect(calls).to eq(%w[SpecMailboxHandlerContinue SpecMailboxHandlerTruthy])
    end

    it 'stops when a handler returns :stop' do
      calls = []
      define_handler('SpecMailboxHandlerStop', calls, :stop)
      define_handler('SpecMailboxHandlerAfterStop', calls, true)
      create_mailbox_handler_fixture!(
        mailbox:,
        class_name: 'SpecMailboxHandlerStop',
        order: 1,
        continue: true
      )
      create_mailbox_handler_fixture!(
        mailbox:,
        class_name: 'SpecMailboxHandlerAfterStop',
        order: 2
      )

      ret = task.send(:handle_message, mailbox, message, dry_run: true)

      expect(ret).to be(true)
      expect(calls).to eq(['SpecMailboxHandlerStop'])
    end

    it 'stops on truthy returns when handler continuation is disabled' do
      calls = []
      define_handler('SpecMailboxHandlerTruthStop', calls, true)
      define_handler('SpecMailboxHandlerNotReached', calls, true)
      create_mailbox_handler_fixture!(
        mailbox:,
        class_name: 'SpecMailboxHandlerTruthStop',
        order: 1,
        continue: false
      )
      create_mailbox_handler_fixture!(
        mailbox:,
        class_name: 'SpecMailboxHandlerNotReached',
        order: 2
      )

      ret = task.send(:handle_message, mailbox, message, dry_run: true)

      expect(ret).to be(true)
      expect(calls).to eq(['SpecMailboxHandlerTruthStop'])
    end
  end
end
