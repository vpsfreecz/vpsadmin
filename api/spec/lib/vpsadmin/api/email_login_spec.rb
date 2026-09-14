require 'spec_helper'

RSpec.describe VpsAdmin::API::EmailLogin do
  let(:user) { SpecSeed.user }
  let(:delivered_mail) { {} }
  let(:request) { build_request }
  let(:context) { { 'flow' => 'token', 'scope' => ['all'], 'lifetime' => 'fixed', 'interval' => 600 } }
  let(:now) { Time.utc(2026, 9, 14, 12) }

  before do
    allow(Time).to receive(:now).and_return(now)
    user.update!(enable_new_device_email_verification: true, enable_multi_factor_auth: false,
                 enable_token_auth: true, password_reset: false, lockout: false,
                 email: 'member@example.test')
    create_user_device!(user:, known: true)
    allow(described_class).to receive(:deliver!) { |_token, code, _request| delivered_mail[:code] = code }
    resolver = instance_double(Resolv, getname: 'ptr.example.test')
    allow(Resolv).to receive(:new).and_return(resolver)
  end

  def start_login
    described_class.start(user, request:, context:, authentication_generation: user.authentication_generation)
  end

  def verify(pending, code: delivered_mail[:code], flow_context: context)
    described_class.process(pending.to_s, request:, context: flow_context, code:)
  end

  it 'requires a usable known cookie and retains history after revocation' do
    device = user.user_devices.find_by!(known: true)
    expect(described_class.required?(user)).to be(true)
    expect(described_class.required?(user, device:)).to be(false)
    device.close
    expect(described_class.required?(user, device:)).to be(true)
    expect(user.user_devices.where(known: true)).to exist
  end

  it 'does not recognize another account or an unfinished device' do
    foreign = create_user_device!(user: SpecSeed.other_user, known: true)
    pending = create_user_device!(user:, known: false)
    expect(described_class.required?(user, device: foreign)).to be(true)
    expect(described_class.required?(user, device: pending)).to be(true)
  end

  it 'exempts only accounts without successful device history' do
    user.user_devices.update_all(known: false)
    expect(described_class.required?(user)).to be(false)
  end

  it 'keeps active MFA authoritative while retaining the preference' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)
    expect(described_class.required?(user)).to be(false)
    expect(user.enable_new_device_email_verification).to be(true)
    user.update!(enable_multi_factor_auth: false)
    expect(described_class.required?(user)).to be(true)
  end

  [5.minutes, 15.minutes, 30.minutes - 1].each do |elapsed|
    it "accepts the code after #{elapsed} seconds and only once" do
      pending = start_login
      expect(pending.valid_to).to eq(now + 30.minutes)
      expect(pending.opts['code_hash']).not_to include(delivered_mail[:code])
      allow(Time).to receive(:now).and_return(now + elapsed)
      expect(verify(pending)).to be_success
      expect { verify(pending) }.to raise_error(described_class::Error, 'email_login_expired')
    end
  end

  it 'rejects a code exactly at the 30-minute deadline' do
    pending = start_login
    allow(Time).to receive(:now).and_return(now + 30.minutes)
    expect { verify(pending) }.to raise_error(described_class::Error, 'email_login_expired')
  end

  it 'requires both the challenge token and its original flow context' do
    pending = start_login
    expect { verify(pending, flow_context: context.merge('scope' => ['user#update'])) }
      .to raise_error(described_class::Error, 'email_login_expired')
    expect(verify(pending)).to be_success
  end

  it 'rejects an unsupported flow before sending email' do
    context['flow'] = 'unsupported'
    expect { start_login }.to raise_error(described_class::Error, 'email_login_expired')
    expect(delivered_mail).to be_empty
    expect(user.auth_tokens).to be_empty
  end

  it 'rotates the code on resend without extending expiry or resetting wrong guesses' do
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(123_456, 654_321)
    pending = start_login
    original_code = delivered_mail[:code]
    expect(verify(pending, code: 'wrong').error).to eq('email_login_invalid')
    allow(Time).to receive(:now).and_return(now + 29.minutes)
    result = described_class.process(pending.to_s, request:, context:, resend: true)
    expect(result).to be_success
    expect(result.auth_token.opts['attempts']).to eq(1)
    expect(result.auth_token.valid_to).to eq(now + 30.minutes)
    expect(verify(pending, code: original_code).error).to eq('email_login_invalid')
    expect(verify(pending)).to be_success
  end

  it 'enforces resend cooldown and a three-send lifetime budget' do
    pending = start_login
    expect(described_class.process(pending.to_s, request:, context:, resend: true).error)
      .to eq('email_login_resend_limited')
    [60, 120].each do |seconds|
      allow(Time).to receive(:now).and_return(now + seconds)
      expect(described_class.process(pending.to_s, request:, context:, resend: true)).to be_success
    end
    allow(Time).to receive(:now).and_return(now + 180)
    expect(described_class.process(pending.to_s, request:, context:, resend: true).error)
      .to eq('email_login_resend_limited')
  end

  it 'exhausts a challenge after five wrong codes' do
    pending = start_login
    5.times { expect(verify(pending, code: 'wrong')).not_to be_success }
    expect { verify(pending) }.to raise_error(described_class::Error, 'email_login_expired')
  end

  it 'keeps the account guess budget across challenges' do
    2.times do
      pending = start_login
      5.times { verify(pending, code: 'wrong') }
    end
    pending = start_login
    expect(verify(pending).error).to eq('email_login_limited')
  end

  it 'limits pending challenges without cancelling earlier attempts' do
    pending = Array.new(3) { start_login }
    expect { start_login }.to raise_error(described_class::Error, 'email_login_limited')
    expect(pending.all? { |token| AuthToken.exists?(token.id) }).to be(true)
  end

  it 'preserves the old generation when enqueueing a resend fails' do
    pending = start_login
    original_code = delivered_mail[:code]
    allow(Time).to receive(:now).and_return(now + 60)
    allow(described_class).to receive(:deliver!).and_raise(described_class::Error, 'email_login_unavailable')
    expect { described_class.process(pending.to_s, request:, context:, resend: true) }
      .to raise_error(described_class::Error, 'email_login_unavailable')
    expect(verify(pending, code: original_code)).to be_success
  end

  it 'rejects an old password result before issuing a challenge' do
    generation = user.authentication_generation
    user.update!(email: 'replacement@example.test')
    expect do
      described_class.start(user, request:, context:, authentication_generation: generation)
    end.to raise_error(described_class::Error, 'email_login_expired')
    expect(described_class).not_to have_received(:deliver!)
  end

  it 'invalidates pending challenges after primary email or security settings change' do
    pending = start_login
    user.update!(email: 'replacement@example.test')
    expect { verify(pending) }.to raise_error(described_class::Error, 'email_login_expired')
  end

  it 'gives forced password reset a fresh five minutes after late verification' do
    user.update!(password_reset: true)
    pending = start_login
    allow(Time).to receive(:now).and_return(now + 29.minutes)
    result = verify(pending)
    expect(result).to be_success
    expect(result.auth_token).to be_reset_password
    expect(result.auth_token.valid_to).to eq(now + 34.minutes)
    expect(result.auth_token.opts).not_to have_key('code_hash')
  end

  it 'rechecks the first-device exemption at the final issuance boundary' do
    user.user_devices.update_all(known: false)
    evidence = described_class.proof(user, 'device')
    expect { described_class.check_authority!(user, evidence) }.not_to raise_error
    create_user_device!(user:, known: true)
    expect { described_class.check_authority!(user, evidence) }
      .to raise_error(described_class::Error, 'email_login_required')
  end

  it 'accepts one mailbox only' do
    expect(described_class.valid_email?('member@example.test')).to be(true)
    ['', 'invalid', "member@example.test\n", 'one@example.test,two@example.test'].each do |email|
      expect(described_class.valid_email?(email)).to be(false)
    end
  end
end
