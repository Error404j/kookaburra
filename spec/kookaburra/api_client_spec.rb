require 'spec_helper'
require 'kookaburra/api_client'

describe Kookaburra::APIClient do
  def url_for(uri)
    URI.join('http://example.com', uri).to_s
  end

  let(:configuration) { double('Configuration', :app_host => 'http://example.com') }

  let(:api) { Kookaburra::APIClient.new(configuration, client) }

  let(:response) { double('RestClient::Response', body: 'foo', code: 200) }

  let(:client) { double('RestClient') }

  shared_examples_for 'any type of HTTP request' do |http_verb|
    context "(#{http_verb})" do
      before(:each) do
        allow(client).to receive(http_verb).and_return(response)
      end

      it 'returns the response body' do
        expect(api.send(http_verb, '/foo')).to eq 'foo'
      end

      it 'raises an UnexpectedResponse if the request is not successful' do
        allow(response).to receive(:code) { 500 }
        allow(client).to receive(http_verb).and_raise(RestClient::Exception.new(response))
        expect{ api.send(http_verb, '/foo') } \
          .to raise_error(Kookaburra::UnexpectedResponse)
      end

      let(:expect_client_to_receive_headers) { ->(expected_headers) {
        # Some HTTP verb methods pass data, some don't, and their arity
        # is different
        allow(client).to receive(http_verb) do |path, data_or_headers, headers|
          headers ||= data_or_headers
          expect(headers).to eq(expected_headers)
          response
        end
      }}

      context 'when custom global headers are specified' do
        let(:api) {
          klass = Class.new(Kookaburra::APIClient) do
            header 'Header-Foo', 'Baz'
            header 'Header-Bar', 'Bam'
          end
          klass.new(configuration, client)
        }

        it "sets global headers on requests" do
          expect_client_to_receive_headers.call('Header-Foo' => 'Baz', 'Header-Bar' => 'Bam')
          api.send(http_verb, '/foo')
        end

        context "and additional headers are specified on a single call" do
          it 'sets both the global and additional headers on the request' do
            expect_client_to_receive_headers.call('Header-Foo' => 'Baz', 'Header-Bar' => 'Bam', 'Yak' => 'Shaved')
            api.send(http_verb, '/foo', nil, 'Yak' => 'Shaved')
          end

          it 'only sets the global headers on subsequent requests' do
            api.send(http_verb, '/foo', nil, 'Yak' => 'Shaved')

            expect_client_to_receive_headers.call('Header-Foo' => 'Baz', 'Header-Bar' => 'Bam')
            api.send(http_verb, '/foo')
          end
        end

        context 'and global header values are overriden by a single call' do
          it 'uses the override value for the the request' do
            expect_client_to_receive_headers.call('Header-Foo' => 'Baz', 'Header-Bar' => 'Yak')
            api.send(http_verb, '/foo', nil, 'Header-Bar' => 'Yak')
          end

          it 'uses the global value for subsequent requests' do
            api.send(http_verb, '/foo', nil, 'Header-Bar' => 'Yak')

            expect_client_to_receive_headers.call('Header-Foo' => 'Baz', 'Header-Bar' => 'Bam')
            api.send(http_verb, '/foo')
          end
        end
      end

      context 'when headers are specified' do
        it 'sets the headers on the request' do
          expected_headers = {'Foo' => 'Bar', 'Baz' => 'Bam'}
          expect_client_to_receive_headers.call(expected_headers)
          api.send(http_verb, '/foo', nil, expected_headers)
        end

        it 'does not set the headers on subsequent requests' do
          api.send(http_verb, '/foo', nil, :foo => :bar)

          expect_client_to_receive_headers.call({})
          api.send(http_verb, '/foo')
        end
      end

      context 'when a custom decoder is specified' do
        let(:api) {
          klass = Class.new(Kookaburra::APIClient) do
          decode_with { |data| :some_decoded_data }
          end
        klass.new(configuration, client)
        }

        it "decodes response bodies from requests" do
          expect(api.send(http_verb, '/foo')).to eq :some_decoded_data
        end
      end
    end
  end

  shared_examples_for 'it encodes request data' do |http_verb|
    context "(#{http_verb})" do
      before(:each) do
        allow(client).to receive(http_verb) { response }
      end

      context 'when a custom encoder is specified' do
        let(:api) {
          klass = Class.new(Kookaburra::APIClient) do
            encode_with { |data|
              raise "Wrong data!" unless data == :some_ruby_data
              :some_encoded_data
            }
          end
          klass.new(configuration, client)
        }

        it "encodes input to requests" do
          expect(client).to receive(http_verb) do |_, data, _|
            expect(data).to eq :some_encoded_data
            response
          end

          api.send(http_verb, '/foo', :some_ruby_data)
        end
      end
    end
  end

  shared_examples_for 'it encodes data as a querystring' do |http_verb|
    context "(#{http_verb})" do
      it 'adds data as querystirng params' do
        expect(client).to receive(http_verb).with(url_for('/foo?bar=baz&yak=shaved'), {}) \
          .and_return(response)
        api.send(http_verb, '/foo', bar: 'baz', yak: 'shaved')
      end
    end
  end

  it_behaves_like 'any type of HTTP request', :get
  it_behaves_like 'any type of HTTP request', :post
  it_behaves_like 'any type of HTTP request', :put
  it_behaves_like 'any type of HTTP request', :delete

  it_behaves_like 'it encodes data as a querystring', :get
  it_behaves_like 'it encodes data as a querystring', :delete

  it_behaves_like 'it encodes request data', :post
  it_behaves_like 'it encodes request data', :put
end
