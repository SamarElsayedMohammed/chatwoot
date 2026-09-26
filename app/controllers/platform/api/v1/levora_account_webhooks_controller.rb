class Platform::Api::V1::LevoraAccountWebhooksController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def create
    url = params[:url].to_s.strip
    if url.blank? || url !~ URI::DEFAULT_PARSER.make_regexp(%w[http https])
      return render json: { error: 'Invalid webhook URL' }, status: :unprocessable_entity
    end

    subscriptions = Array(params[:subscriptions]).map(&:to_s)
    subscriptions = Webhook::ALLOWED_WEBHOOK_EVENTS if subscriptions.blank?
    invalid = subscriptions.uniq - Webhook::ALLOWED_WEBHOOK_EVENTS
    if invalid.any?
      return render json: { error: 'Invalid webhook subscriptions' }, status: :unprocessable_entity
    end

    webhook = @resource.webhooks.find_by(url: url)
    if webhook.present?
      webhook.update!(name: params[:name].presence || webhook.name || 'Levora', subscriptions: subscriptions)
      return render json: { id: webhook.id, secret: webhook.secret }, status: :ok
    end

    webhook = @resource.webhooks.create!(
      name: params[:name].presence || 'Levora',
      url: url,
      subscriptions: subscriptions
    )

    render json: { id: webhook.id, secret: webhook.secret }, status: :created
  end

  private

  def set_resource
    @resource = Account.find(params[:account_id])
  end
end
