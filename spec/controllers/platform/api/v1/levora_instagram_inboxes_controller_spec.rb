require 'rails_helper'

RSpec.describe 'Platform Levora Instagram Inboxes API', type: :request do
  let(:account) { create(:account) }
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }
  let(:params) do
    {
      instagram_id: '17841400123456789',
      access_token: 'ig-access-token-test',
      inbox_name: 'Levora Instagram',
      request_id: 'connection:550e8400-e29b-41d4-a716-446655440000'
    }
  end

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: account)
    allow_any_instance_of(Channel::Instagram).to receive(:subscribe).and_return(true)
  end

  it 'is unavailable while the explicit feature flag is disabled' do
    allow(ENV).to receive(:fetch).with('LEVORA_INSTAGRAM_PROVISIONING_ENABLED', 'true').and_return('false')
    post endpoint, params: params, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(account.instagram_channels).to be_empty
  end

  context 'when provisioning Instagram inbox' do
    it 'creates an Instagram channel and inbox' do
      post endpoint, params: params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'remote_account_id' => account.id,
        'provider_instagram_id' => params[:instagram_id],
        'status' => 'created'
      )
      expect(account.instagram_channels.find_by!(instagram_id: params[:instagram_id]).inbox).to be_present
    end

    it 'auto-provisions workspace user and assigns them to the inbox when user_email is provided' do
      user_params = params.merge(
        user_email: 'workspace-owner@levora.ai',
        user_name: 'Workspace Owner',
        user_password: 'SecurePassword123!'
      )

      expect {
        post endpoint, params: user_params, headers: headers, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      created_user = User.find_by!(email: 'workspace-owner@levora.ai')
      expect(account.administrators).to include(created_user)

      inbox = account.instagram_channels.find_by!(instagram_id: params[:instagram_id]).inbox
      expect(inbox.inbox_members.map(&:user_id)).to include(created_user.id)
    end

    it 'returns the existing inbox on a duplicate instagram id request' do
      post endpoint, params: params, headers: headers, as: :json
      first_inbox_id = response.parsed_body.fetch('remote_inbox_id')

      post endpoint, params: params.merge(request_id: 'connection:another-request'), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('remote_inbox_id' => first_inbox_id, 'status' => 'existing')
      expect(account.instagram_channels.where(instagram_id: params[:instagram_id]).count).to eq(1)
    end

    it 'rejects an invalid request id before creating a channel' do
      post endpoint, params: params.merge(request_id: 'invalid request id'), headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(account.instagram_channels).to be_empty
    end
  end

  def endpoint
    "/platform/api/v1/accounts/#{account.id}/levora/instagram-inboxes"
  end
end
