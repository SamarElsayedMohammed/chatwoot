require 'rails_helper'

RSpec.describe 'Platform Levora Agents API', type: :request do
  let(:account) { create(:account) }
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }
  let(:endpoint) { "/platform/api/v1/accounts/#{account.id}/levora/agents" }

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: account)
  end

  it 'creates a confirmed account agent with the platform token' do
    expect do
      post endpoint,
           params: { name: 'Support Agent', email: 'support-agent@example.com', password: 'Agentpass1!', role: 'agent' },
           headers: headers,
           as: :json
    end.to change(User, :count).by(1)
      .and change(account.account_users, :count).by(1)

    expect(response).to have_http_status(:created)
    created = User.from_email('support-agent@example.com')
    expect(created).to be_confirmed
    expect(created.valid_password?('Agentpass1!')).to be(true)
    expect(account.users.reload).to include(created)
    expect(response.parsed_body['id']).to eq(created.id)
  end

  it 'adds an existing user to the account without a new invitation email' do
    existing = create(:user, email: 'existing-agent@example.com', name: 'Existing Agent')

    expect do
      post endpoint,
           params: { name: 'Existing Agent', email: existing.email, role: 'agent' },
           headers: headers,
           as: :json
    end.not_to change(User, :count)

    expect(response).to have_http_status(:created)
    expect(account.users.reload).to include(existing)
    expect(existing.reload).to be_confirmed
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
