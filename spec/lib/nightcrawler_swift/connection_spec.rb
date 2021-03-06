require "spec_helper"

describe NightcrawlerSwift::Connection do

  let :options do
    {
      bucket: "my-bucket-name",
      tenant_name: "tenant_username1",
      username: "username1",
      password: "some-pass",
      auth_url: "https://auth-url-com:123/v3/auth/tokens",
      max_age: 31536000 # 1 year
    }
  end

  let :opts do
    options
  end

  subject do
    NightcrawlerSwift::Connection.new
  end

  before do
    NightcrawlerSwift.configure opts
    NightcrawlerSwift.logger = Logger.new(StringIO.new)
  end

  describe "#connect!" do
    let :auth_json do
      {
        auth: {
          identity: {
            methods: [
                "password"
            ],
            password: {
              user: {
               domain: {
                 id: "default"
               },
               name: opts[:username],
               password: opts[:password]
              }
            }
          },
          scope: {
            project: {
              domain: {
                id: "default"
              },
              name: opts[:tenant_name]
            }
          }
        }
      }.to_json
    end

    let :auth_success_response do
      path = File.join(File.dirname(__FILE__), "../..", "fixtures/auth_success.json")
      file_contents = JSON.parse(File.read(File.expand_path(path)))
      headers = file_contents["headers"].reduce({}) do |h, item|
        key, value = item
        h[key.downcase.gsub("-", "_").to_sym] = value
        h
      end
      OpenStruct.new(headers: headers, body: file_contents["body"].to_json)
    end

    let :auth_success_json do
      {
        "headers" => auth_success_response.headers,
        "body" => JSON.parse(auth_success_response.body)
      }
    end

    describe "when it connects" do
      let :resource do
        RestClient::Resource.new(
          opts[:auth_url],
          verify_ssl: NightcrawlerSwift.options.verify_ssl,
          timeout: NightcrawlerSwift.options.timeout
        )
      end

      before do
        allow(RestClient::Resource).to receive(:new).and_return(resource)
        allow(resource).to receive(:post).
          with(auth_json, content_type: :json, accept: :json).
          and_return(auth_success_response)
      end

      it "stores the auth response body" do
        subject.connect!
        # This test uses 'eq' instead of 'eql' because in Ruby 1.9.x the method
        # 'equal?' is different than '==' making this test fail
        expect(subject.auth_response.body).to eq(auth_success_json["body"])
      end

      it "stores the auth response headers" do
        subject.connect!
        expect(subject.auth_response.headers).to eq(auth_success_json["headers"])
      end

      it "stores the token id" do
        subject.connect!
        expect(subject.token_id).not_to be_nil
        expect(subject.token_id).to eql(auth_success_json["headers"][:x_subject_token])
      end

      it "stores the expires_at" do
        subject.connect!
        expires_at = DateTime.parse(auth_success_json["body"]["token"]["expires_at"]).to_time
        expect(subject.expires_at).to eql(expires_at)
      end

      it "stores the catalog" do
        subject.connect!
        expect(subject.catalog).to eql(auth_success_json["body"]["token"]["catalog"][0])
        expect(subject.catalog["type"]).to eql("object-store")
      end

      it "stores the admin_url" do
        subject.connect!
        expect(subject.admin_url).to eql(auth_success_json["body"]["token"]["catalog"][0]["endpoints"][0]["url"])
      end

      it "stores the upload_url" do
        subject.connect!
        admin_url = subject.admin_url
        expect(subject.upload_url).to eql("#{admin_url}/#{opts[:bucket]}")
      end

      it "stores the public_url" do
        subject.connect!
        expect(subject.public_url).to eql(auth_success_json["body"]["token"]["catalog"][0]["endpoints"][2]["url"])
      end

      it "stores the internal_url" do
        subject.connect!
        expect(subject.internal_url).to eql(auth_success_json["body"]["token"]["catalog"][0]["endpoints"][1]["url"])
      end

      it "returns self" do
        expect(subject.connect!).to eql(subject)
      end

      context "and there isn't any catalog configured" do
        before do
          auth_success_json["body"]["token"]["catalog"] = []
          allow(subject).to receive(:auth_response).and_return(OpenStruct.new(auth_success_json))
        end

        it "raises NightcrawlerSwift::Exceptions::ConfigurationError" do
          expect { subject.connect! }.to raise_error(NightcrawlerSwift::Exceptions::ConfigurationError)
        end
      end

      context "with a configured admin_url" do
        let(:new_admin_url){ "http://some-new-admin-url" }
        let(:opts) { options.merge(admin_url: new_admin_url) }

        it "uses the given url" do
          subject.connect!
          expect(subject.admin_url).to eql new_admin_url
        end
      end

      context "with a configured public_url" do
        let(:new_public_url) { "http://some-new-public-url" }
        let(:opts) { options.merge(public_url: new_public_url) }

        it "uses the given url" do
          subject.connect!
          expect(subject.public_url).to eql new_public_url
        end
      end
    end

    describe "when some error happens" do
      before do
        allow(RestClient::Resource).to receive(:new).and_raise(StandardError.new("error!"))
      end

      it "raises NightcrawlerSwift::Exceptions::ConnectionError" do
        expect { subject.connect! }.to raise_error NightcrawlerSwift::Exceptions::ConnectionError
      end
    end
  end

  describe "#connected?" do
    it "checks if token_id exists and is still valid" do
      expect(subject.token_id).to be_nil
      expect(subject.connected?).to be false

      expires_at = DateTime.now.to_time + 11
      allow(subject).to receive(:expires_at).and_return(expires_at)
      allow(subject).to receive(:token_id).and_return("token")
      expect(subject.connected?).to be true
    end
  end

end
