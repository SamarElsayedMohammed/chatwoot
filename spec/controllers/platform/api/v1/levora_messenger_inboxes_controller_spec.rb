require 'rails_helper'

RSpec.describe 'Platform Levora Messenger Inboxes API', type: :request do
  let(:account) { create(:account) }
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }
  let(:params) do
    {
      page_id: '123456789012345',
      page_access_token: 'page-token-not-logged',
      user_access_token: 'user-token-not-logged',
      inbox_name: 'Levora Messenger',
      request_id: 'connection:550e8400-e29b-41d4-a716-446655440000'
    }
  end

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: account)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
  end

  it 'is unavailable while the explicit feature flag is disabled' do
    post endpoint, params: params, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(account.facebook_pages).to be_empty
  end

  context 'when the explicit feature flag is enabled' do
    before do
      allow(ENV).to receive(:fetch).with('LEVORA_MESSENGER_PROVISIONING_ENABLED', 'false').and_return('true')
    end

    it 'creates a Facebook channel and inbox without returning tokens' do
      post endpoint, params: params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'remote_account_id' => account.id,
        'provider_page_id' => params[:page_id],
        'status' => 'created'
      )
      expect(response.body).not_to include(params[:page_access_token], params[:user_access_token])
      expect(account.facebook_pages.find_by!(page_id: params[:page_id]).inbox).to be_present
    end

    it 'returns the existing inbox on a duplicate page request' do
      post endpoint, params: params, headers: headers, as: :json
      first_inbox_id = response.parsed_body.fetch('remote_inbox_id')

      post endpoint, params: params.merge(request_id: 'connection:another-request'), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('remote_inbox_id' => first_inbox_id, 'status' => 'existing')
      expect(account.facebook_pages.where(page_id: params[:page_id]).count).to eq(1)
    end

    it 'creates an inbox for an existing Facebook channel without one' do
      facebook_channel = account.facebook_pages.create!(
        page_id: params[:page_id],
        page_access_token: params[:page_access_token],
        user_access_token: params[:user_access_token]
      )

      post endpoint, params: params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'remote_inbox_id' => facebook_channel.reload.inbox.id,
        'status' => 'created'
      )
    end

    it 'rejects an invalid request id before creating a channel' do
      post endpoint, params: params.merge(request_id: 'invalid request id'), headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(account.facebook_pages).to be_empty
    end
  end

  def endpoint
    "/platform/api/v1/accounts/#{account.id}/levora/messenger-inboxes"
  end
end
