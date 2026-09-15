class Platform::Api::V1::LevoraInstagramInboxesController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible
  before_action :ensure_provisioning_enabled

  def create
    instagram_id = required_string_param(:instagram_id, max_length: 255)
    access_token = required_string_param(:access_token, max_length: 4096)
    inbox_name = required_string_param(:inbox_name, max_length: 255)
    validate_request_id!

    expires_at = params[:expires_at].present? ? Time.zone.parse(params[:expires_at].to_s) : 60.days.from_now

    @instagram_channel = @resource.instagram_channels.includes(:inbox).find_by(instagram_id: instagram_id)
    @created = false

    ActiveRecord::Base.transaction do
      setup_workspace_user if params[:user_email].present?

      if @instagram_channel.blank?
        @instagram_channel = Channel::Instagram.create!(
          account: @resource,
          instagram_id: instagram_id,
          access_token: access_token,
          expires_at: expires_at
        )
        @inbox = @resource.inboxes.create!(name: inbox_name, channel: @instagram_channel)
        @created = true
      else
        @instagram_channel.update!(access_token: access_token, expires_at: expires_at)
        @inbox = @instagram_channel.inbox

        if @inbox.blank?
          @inbox = @resource.inboxes.create!(name: inbox_name, channel: @instagram_channel)
          @created = true
        end
      end

      assign_inbox_members
      set_avatar(params[:avatar_url])
    end

    render json: response_body, status: @created ? :created : :ok
  rescue ActiveRecord::RecordNotUnique
    @instagram_channel = Channel::Instagram.includes(:inbox).find_by!(instagram_id: instagram_id, account: @resource)
    @inbox = @instagram_channel.inbox
    @created = false

    assign_inbox_members
    render json: response_body, status: :ok
  end

  private

  def set_resource
    @resource = Account.find(params[:account_id])
  end

  def ensure_provisioning_enabled
    return if ENV.fetch('LEVORA_INSTAGRAM_PROVISIONING_ENABLED', 'true') == 'true'

    render json: { error: 'Not found' }, status: :not_found
  end

  def setup_workspace_user
    email = params[:user_email].to_s.strip.downcase
    return if email.blank?

    name = params[:user_name].presence || email.split('@').first.titleize
    password = params[:user_password].presence || Devise.friendly_token[0, 20]
    role = params[:user_role].presence || 'administrator'

    user = User.from_email(email) || User.new(email: email, name: name, password: password)
    user.name = name if user.name.blank?
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    user.save!

    @platform_app.platform_app_permissibles.find_or_create_by!(permissible: user)

    account_user = @resource.account_users.find_or_initialize_by(user_id: user.id)
    account_user.role = role
    account_user.save!

    user
  end

  def assign_inbox_members
    return if @inbox.blank?

    @resource.account_users.find_each do |account_user|
      @inbox.inbox_members.find_or_create_by!(user_id: account_user.user_id)
    end
  end

  def set_avatar(avatar_url)
    return if @inbox.blank? || avatar_url.blank?

    Avatar::AvatarFromUrlJob.perform_later(@inbox, avatar_url)
  rescue StandardError => e
    Rails.logger.warn "LevoraInstagramInboxesController: Failed to schedule avatar job: #{e.message}"
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
      provider_instagram_id: @instagram_channel.instagram_id,
      status: @created ? 'created' : 'existing'
    }
  end
end
