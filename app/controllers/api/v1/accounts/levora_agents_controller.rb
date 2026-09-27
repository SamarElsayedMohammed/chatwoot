class Api::V1::Accounts::LevoraAgentsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def create
    email = agent_params[:email].to_s.downcase.strip
    raise ActionController::ParameterMissing, :email if email.blank?

    name = agent_params[:name].to_s.strip
    name = email.split('@').first if name.blank?
    role = agent_params[:role].to_s == 'administrator' ? :administrator : :agent
    supplied_password = agent_params[:password].to_s
    password = chatwoot_password(supplied_password)

    @agent = Current.account.with_lock do
      ActiveRecord::Base.transaction do
        user = User.from_email(email)
        already_member = user.present? && Current.account.account_users.exists?(user_id: user.id)
        raise AgentBuilder::LimitExceededError if !already_member && !can_add_agent?

        user = confirm_user(user, email, name, supplied_password, password)
        account_user = Current.account.account_users.find_or_initialize_by(user_id: user.id)
        account_user.role = role
        account_user.inviter_id ||= Current.user.id
        account_user.save!
        user
      end
    end
  rescue AgentBuilder::LimitExceededError => e
    render_payment_required(e.message)
  end

  private

  def agent_params
    source = params[:levora_agent].presence || params
    source.permit(:name, :email, :password, :role)
  end

  def can_add_agent?
    Current.account.usage_limits[:agents] > Current.account.account_users.count
  end

  def confirm_user(user, email, name, supplied_password, password)
    if user
      user.name = name if user.name.blank?
      user.skip_confirmation!
      if supplied_password.present? && password == supplied_password
        user.password = password
        user.password_confirmation = password
      end
      user.save!
      return user
    end

    User.new(email: email, name: name, password: password, password_confirmation: password).tap do |new_user|
      new_user.skip_confirmation!
      new_user.save!
    end
  end

  def chatwoot_password(supplied)
    return supplied if password_compliant?(supplied)

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
