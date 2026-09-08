class Platform::Api::V1::LevoraMessengerInboxesController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible
  before_action :ensure_provisioning_enabled

  def create
    page_id = required_string_param(:page_id, max_length: 255)
    page_access_token = required_string_param(:page_access_token, max_length: 4096)
    user_access_token = required_string_param(:user_access_token, max_length: 4096)
    inbox_name = required_string_param(:inbox_name, max_length: 255)
    validate_request_id!

    @facebook_channel = @resource.facebook_pages.includes(:inbox).find_by(page_id: page_id)
    @created = false

    if @facebook_channel.blank?
      ActiveRecord::Base.transaction do
        @facebook_channel = @resource.facebook_pages.create!(
          page_id: page_id,
          page_access_token: page_access_token,
          user_access_token: user_access_token
        )
        @inbox = @resource.inboxes.create!(name: inbox_name, channel: @facebook_channel)
        @created = true
      end
    else
      @inbox = @facebook_channel.inbox

      if @inbox.blank?
        @inbox = @resource.inboxes.create!(name: inbox_name, channel: @facebook_channel)
        @created = true
      end
    end

    render json: response_body, status: @created ? :created : :ok
  rescue ActiveRecord::RecordNotUnique
    @facebook_channel = @resource.facebook_pages.includes(:inbox).find_by!(page_id: page_id)
    @inbox = @facebook_channel.inbox
    @created = false

    render json: response_body, status: :ok
  end

  private

  def set_resource
    @resource = Account.find(params[:account_id])
  end

  def ensure_provisioning_enabled
    return if ENV.fetch('LEVORA_MESSENGER_PROVISIONING_ENABLED', 'false') == 'true'

    render json: { error: 'Not found' }, status: :not_found
  end

  def required_string_param(name, max_length:)
    value = params.require(name).to_s
    raise ActionController::BadRequest, "Invalid #{name}" if value.blank? || value.length > max_length

    value
  end

  def validate_request_id!
    request_id = required_string_param(:request_id, max_length: 128)
    raise ActionController::BadRequest, 'Invalid request_id' unless request_id.match?(/\A[A-Za-z0-9._:-]+\z/)
  end

  def response_body
    {
      remote_account_id: @resource.id,
      remote_inbox_id: @inbox.id,
      provider_page_id: @facebook_channel.page_id,
      status: @created ? 'created' : 'existing'
    }
  end
end
