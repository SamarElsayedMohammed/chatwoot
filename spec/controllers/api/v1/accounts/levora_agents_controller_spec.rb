require 'rails_helper'

RSpec.describe 'Levora Agents API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  describe 'POST /api/v1/accounts/{account.id}/levora/agents' do
    let(:params) { { name: 'New Agent', email: 'new-agent@example.com', password: 'Agentpass1!', role: 'agent' } }

    it 'returns unauthorized when the caller is not authenticated' do
      post "/api/v1/accounts/#{account.id}/levora/agents", params: params, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates a confirmed account agent without sending an invitation email' do
      expect do
        post "/api/v1/accounts/#{account.id}/levora/agents",
             params: params,
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(User, :count).by(1)
        .and change(account.account_users, :count).by(1)

      expect(response).to have_http_status(:success)
      created = User.from_email('new-agent@example.com')
      expect(created).to be_confirmed
      expect(created.valid_password?('Agentpass1!')).to be(true)
      expect(account.users.reload).to include(created)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'adds an existing Chatwoot user to the account' do
      existing = create(:user, email: 'existing-agent@example.com', name: 'Existing Agent')

      expect do
        post "/api/v1/accounts/#{account.id}/levora/agents",
             params: { name: 'Existing Agent', email: existing.email, role: 'agent' },
             headers: admin.create_new_auth_token,
             as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:success)
      expect(account.users.reload).to include(existing)
      expect(existing.reload).to be_confirmed
    end
  end
end
