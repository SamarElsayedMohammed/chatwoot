class Platform::Api::V1::LevoraAgentsController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def create
    email = params[:email].to_s.downcase.strip
    raise ActionController::ParameterMissing, :email if email.blank?

    name = params[:name].to_s.strip
    name = email.split('@').first if name.blank?
    role = params[:role].to_s == 'administrator' ? 'administrator' : 'agent'
    supplied_password = params[:password].to_s
    password = password_compliant?(supplied_password) ? supplied_password : generated_password

    user = nil
    account_user = nil

    ActiveRecord::Base.transaction do
      user = User.from_email(email)
      if user
        user.name = name if user.name.blank?
        user.skip_confirmation!
        if password_compliant?(supplied_password)
          user.password = supplied_password
          user.password_confirmation = supplied_password
        end
        user.save!
      else
        user = User.new(email: email, name: name, password: password, password_confirmation: password)
        user.skip_confirmation!
        user.save!
      end

      @platform_app.platform_app_permissibles.find_or_create_by!(permissible: user)
      account_user = @resource.account_users.find_or_initialize_by(user_id: user.id)
      account_user.role = role
      account_user.save!

      if params[:inbox_id].present?
        inbox = @resource.inboxes.find(params[:inbox_id])
        inbox.inbox_members.find_or_create_by!(user_id: user.id)
      end
    end

    render json: {
      id: user.id,
      name: user.name,
      email: user.email,
      role: account_user.role
    }, status: :created
  end

  private

  def set_resource
    @resource = Account.find(params[:account_id])
  end

  def generated_password
    "1!aA#{SecureRandom.alphanumeric(12)}"
  end

  def password_compliant?(value)
    value.length >= 6 &&
      value.match?(/[A-Z]/) &&
      value.match?(/[a-z]/) &&
      value.match?(/\d/) &&
      value.match?(/[!@#$%^&*()_+\-=\[\]{}|']/)
  end
end
