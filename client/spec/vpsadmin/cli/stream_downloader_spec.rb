# frozen_string_literal: true

require 'spec_helper'
require 'digest'

FakeDownloadResponse = Struct.new(:code, :body) do
  def read_body
    yield body
  end
end

class FakeDownloadHttp
  Request = Struct.new(:path, :headers, keyword_init: true)

  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def request_get(path, headers)
    @requests << Request.new(path: path, headers: headers)
    yield @responses.shift
  end
end

RSpec.describe VpsAdmin::CLI::StreamDownloader do
  def fake_api(dl_check)
    FakeRecord.new(
      snapshot_download: FakeCollection.new([], show_records: {
                                       dl_check.id => dl_check
                                     })
    )
  end

  it 'downloads using the URL port and request URI' do
    payload = 'payload'
    dl_check = FakeRecord.new(
      id: 123,
      ready: true,
      size: 1,
      sha256sum: Digest::SHA256.hexdigest(payload)
    )
    dl = FakeRecord.new(
      id: dl_check.id,
      url: 'http://downloads.example.test:8080/files/archive.tar.gz?token=abc'
    )
    http = FakeDownloadHttp.new(FakeDownloadResponse.new('200', payload))
    out = StringIO.new

    allow(Net::HTTP).to receive(:start).and_yield(http)

    described_class.download(fake_api(dl_check), dl, out, progress: nil)

    expect(Net::HTTP).to have_received(:start)
      .with('downloads.example.test', 8080, nil, nil, nil, nil, { use_ssl: false })
    expect(http.requests.map(&:path)).to eq(['/files/archive.tar.gz?token=abc'])
    expect(out.string).to eq(payload)
  end

  it 'resumes from the existing position and verifies the full checksum' do
    existing = 'old'
    payload = 'new'
    dl_check = FakeRecord.new(
      id: 124,
      ready: true,
      size: 1,
      sha256sum: Digest::SHA256.hexdigest(existing + payload)
    )
    dl = FakeRecord.new(id: dl_check.id, url: 'https://downloads.example.test/file.dat')
    http = FakeDownloadHttp.new(FakeDownloadResponse.new('206', payload))
    out = StringIO.new(existing.dup)

    allow(Net::HTTP).to receive(:start).and_yield(http)

    described_class.download(
      fake_api(dl_check),
      dl,
      out,
      progress: nil,
      position: existing.bytesize
    )

    expect(Net::HTTP).to have_received(:start)
      .with('downloads.example.test', 443, nil, nil, nil, nil, { use_ssl: true })
    expect(http.requests.first.headers).to eq('Range' => "bytes=#{existing.bytesize}-")
    expect(out.string).to eq(existing + payload)
  end

  it 'raises when the checksum does not match' do
    payload = 'payload'
    dl_check = FakeRecord.new(
      id: 125,
      ready: true,
      size: 1,
      sha256sum: Digest::SHA256.hexdigest('different')
    )
    dl = FakeRecord.new(id: dl_check.id, url: 'http://downloads.example.test/file.dat')
    http = FakeDownloadHttp.new(FakeDownloadResponse.new('200', payload))

    allow(Net::HTTP).to receive(:start).and_yield(http)

    expect do
      described_class.download(fake_api(dl_check), dl, StringIO.new, progress: nil)
    end.to raise_error(
      VpsAdmin::CLI::DownloadError,
      'The sha256sum does not match, retry the download'
    )
  end
end
