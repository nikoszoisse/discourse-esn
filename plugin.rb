# name: discourse-esners
# about: esners magic for Discourse
# version: 1.0.1
# author: Leo McArdle

enabled_site_setting :esners_enabled

after_initialize do
  require_dependency File.expand_path("../jobs/mozillians_magic.rb", __FILE__)

  module EsnersAuthExtensions
    def after_authenticate(auth_token)
      result = super(auth_token)

      user = result.user
      if SiteSetting.esners_enabled?
        Jobs.enqueue(:esners_magic, user_id: user.id) if user.try(:id)
      end

      result
    end

    def after_create_account(user, auth)
      super(user, auth)

      if SiteSetting.esners_enabled?
        Jobs.enqueue(:esners_magic, user_id: user.id)
      end
    end
  end

  Auth::Authenticator.descendants.each do |auth_class|
    auth_class.send(:prepend, EsnersAuthExtensions)
  end

  module EsnersSessionExtensions
    def update_esners
      params.require(:login)

      unless SiteSetting.esners_enabled?
        render nothing: true, status: 500
        return
      end

      RateLimiter.new(nil, "esners-update-hr-#{request.remote_ip}", 6, 1.hour).performed!
      RateLimiter.new(nil, "esners-update-min-#{request.remote_ip}", 3, 1.minute).performed!

      user = User.find_by_username_or_email(params[:login])
      user_presence = user.present? && user.id != Discourse::SYSTEM_USER_ID
      if user_presence
        Jobs.enqueue(:esners_magic, user_id: user.id)
      end

      json = { result: "ok" }

      render json: json

    rescue RateLimiter::LimitExceeded
      render_json_error(I18n.t("rate_limiter.slow_down"))
    end
  end

  SessionController.send(:prepend, EsnersSessionExtensions)

  Discourse::Application.routes.append do
    resources :session, id: USERNAME_ROUTE_FORMAT, only: [:create, :destroy, :become] do
      collection do
        post "update_esners"
      end
    end
  end

end
