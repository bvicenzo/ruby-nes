# frozen_string_literal: true

RSpec.describe TestRoms::Downloader do
  describe '#get' do
    subject(:downloader) { described_class.new }

    let(:url) { 'https://upstream.example/roms/95d8f621/other/nestest.nes' }
    let(:connection_settings) { ['upstream.example', 443, { use_ssl: true, open_timeout: 10, read_timeout: 30 }] }

    context 'when the request cannot reach the server' do
      before { allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'getaddrinfo: nodename nor servname') }

      it do
        expect { downloader.get(url) }
          .to raise_error(TestRoms::DownloadError, /#{Regexp.escape(url)}.*getaddrinfo/)
      end
    end

    context 'when the server answers' do
      let(:connection) { instance_double(Net::HTTP) }

      before { allow(Net::HTTP).to receive(:start).with(*connection_settings).and_yield(connection) }

      context 'but the response is not valid HTTP' do
        before { allow(connection).to receive(:get).and_raise(Net::HTTPBadResponse, 'wrong status line') }

        it do
          expect { downloader.get(url) }
            .to raise_error(TestRoms::DownloadError, /#{Regexp.escape(url)}.*wrong status line/)
        end
      end

      context 'but with a status other than 200' do
        let(:response) { instance_double(Net::HTTPNotFound, code: '404', body: 'Not Found') }

        before { allow(connection).to receive(:get).with('/roms/95d8f621/other/nestest.nes').and_return(response) }

        it do
          expect { downloader.get(url) }
            .to raise_error(TestRoms::DownloadError, /#{Regexp.escape(url)} answered 404/)
        end
      end

      context 'and with 200' do
        let(:response) { instance_double(Net::HTTPOK, code: '200', body: "\x4E\x45\x53\x1A".b) }

        before { allow(connection).to receive(:get).with('/roms/95d8f621/other/nestest.nes').and_return(response) }

        it 'returns the body, having waited no longer than the connection timeouts', :aggregate_failures do
          expect(downloader.get(url)).to eq("\x4E\x45\x53\x1A".b)
          expect(Net::HTTP).to have_received(:start).with(*connection_settings)
        end
      end
    end
  end
end
