require 'spec_helper'
require 'dpl/provider/cloudcontrol'

describe DPL::Provider::CloudControl do
  subject :provider do
    described_class.new(DummyContext.new, :deployment => 'foo_app/default', :email => 'foo@test.com', :password => 'password')
  end

  its(:app_name) { should == 'foo_app' }
  its(:dep_name) { should == 'default' }

  its(:needs_key?) { should be true }

  describe 'constructor' do
    it 'with wrong arguments' do
      expect {
        described_class.new(DummyContext.new, :foo_dep => 'foo_app/default', :email => 'foo@test.com', :password => 'password')
      }.to raise_error(DPL::Error)
    end
  end

  it '#check_auth should call #headers_with_token' do
    provider.should receive(:headers_with_token)
    provider.check_auth.should
  end

  describe '#check_app' do
    it 'on deployment found' do
      provider.should receive(:api_call).and_return double(
        :code => '200',
        :body => '{"branch":"foo_repo.git"}'
      )
      provider.instance_variable_get(:@repository).should be_nil
      provider.check_app
      provider.instance_variable_get(:@repository).should == 'foo_repo.git'
    end

    it 'on deployment not found' do
      provider.should receive(:api_call).and_return double(:code => '410')
      expect { provider.check_app }.to raise_error(DPL::Error)
    end
  end

  describe '#setup_key' do
    before do
      File.should receive(:read).with('file').and_return('foo_key')
      provider.should receive(:user).and_return({ 'username' => 'foo_user' })
    end

    it 'on api success' do
      provider.should receive(:api_call).with('POST', '/user/foo_user/key', '{"key":"foo_key"}').and_return double(
          :code => '200',
          :body => '{ "key": "foo_key", "key_id": "foo_key_id"}'
        )

      provider.instance_variable_get(:@ssh_key_id).should be_nil
      provider.setup_key 'file'
      provider.instance_variable_get(:@ssh_key_id).should == 'foo_key_id'
    end

    it 'on api failure' do
      provider.should receive(:api_call).with('POST', '/user/foo_user/key', '{"key":"foo_key"}').and_return double(:code => '401')

      expect { provider.setup_key 'file' }.to raise_error(DPL::Error)
    end
  end

  describe '#remove_key' do
    before do
      provider.instance_variable_set(:@ssh_key_id, 'foo_key_id')
      provider.should receive(:user).and_return({ 'username' => 'foo_user' })
    end

    it 'on api success' do
      provider.should receive(:api_call).with('DELETE', '/user/foo_user/key/foo_key_id').and_return double(:code => '204')
      provider.remove_key
    end

    it 'on api failure' do
      provider.should receive(:api_call).with('DELETE', '/user/foo_user/key/foo_key_id').and_return double(:code => '410')
      expect { provider.remove_key }.to raise_error(DPL::Error)
    end
  end

  it '#push_app shuld deploy the app' do
    provider.instance_variable_set(:@repository, 'foo_repo.git')
    context = double(:shell)
    context.should receive(:shell).with("git push foo_repo.git master;")
    provider.should receive(:context).and_return context
    provider.should receive(:deploy_app)

    provider.push_app
  end

  describe 'private method' do
    describe '#get_token' do
      it 'on api success' do
        request = double()
        request.should receive(:basic_auth).with('foo@test.com', 'password')
        Net::HTTP::Post.should receive(:new).with('/token/').and_return request

        provider.instance_variable_get(:@http).should receive(:request).and_return double(
          :code => '200',
          :body => '{ "token": "foo_token"}'
        )

        provider.instance_eval { get_token }.should == { 'token' => 'foo_token' }
      end

      it 'on api failure' do
        provider.instance_variable_get(:@http).should receive(:request).and_return double(:code => '401')

        expect do
          provider.instance_eval { get_token }
        end.to raise_error(DPL::Error)
      end
    end

    it '#headers_with_token should return headers' do
      provider.should receive(:get_token).and_return({ 'token' => 'foo_token' })
      expected_return = {
        'Authorization' => 'cc_auth_token="foo_token"',
        'Content-Type' => 'application/json'
      }

      provider.instance_eval { headers_with_token }.should == expected_return
    end

    describe '#get_headers' do
      let(:expected_args) { [ 'GET', '/user/', nil, {'foo' => 'headers'} ] }

      before do
        provider.should receive(:headers_with_token).and_return({ 'foo' => 'headers' })
      end

      it 'on token valid' do
        provider.should receive(:api_call).with(*expected_args).and_return double(:code => '200')
        provider.instance_eval { get_headers }.should == { 'foo' => 'headers' }
      end

      it 'on token expired' do
        provider.should receive(:api_call).with(*expected_args).and_return double(:code => '401')
        provider.should receive(:headers_with_token).with({ :new_token => true})

        provider.instance_eval { get_headers }
      end
    end

    it '#api_call should send request' do
      expected_args = [ "foo_method", "foo_path", "\"foo\":\"data\"", {"foo"=>"headers"} ]
      provider.instance_variable_get(:@http).should receive(:send_request).with(*expected_args)

      provider.instance_eval do
        api_call('foo_method', 'foo_path', '"foo":"data"', { 'foo' => 'headers'})
      end
    end

    describe '#deploy_app' do
      it 'on api success' do
        provider.should receive(:api_call).with('PUT', '/app/foo_app/deployment/default', '{"version":-1}').and_return double(:code => '200')
        provider.instance_eval { deploy_app }
      end

      it 'on api failure' do
        provider.should receive(:api_call).with('PUT', '/app/foo_app/deployment/default', '{"version":-1}').and_return double(:code => '410')
        expect do
          provider.instance_eval { deploy_app }
        end.to raise_error(DPL::Error)
      end
    end

    describe '#user' do
      it 'on api success' do
        provider.should receive(:api_call).with('GET', '/user/').and_return double(
          :code => '200',
          :body => '["foo_user"]'
        )

        provider.instance_eval { user }.should == 'foo_user'
      end

      it 'on api failure' do
        provider.should receive(:api_call).with('GET', '/user/').and_return double(:code => '410')

        expect do
          provider.instance_eval { user }
        end.to raise_error(DPL::Error)
      end
    end
  end
end
