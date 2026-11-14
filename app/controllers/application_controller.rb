class ApplicationController < ActionController::API
  rescue_from Igdb::Client::ApiError do |e|
    render json: { error: e.message }, status: (e.status == 429 ? 429 : :bad_gateway)
  end

  rescue_from Igdb::TokenManager::AuthError do |e|
    Rails.logger.error(e.message)
    render json: { error: "Could not authenticate with IGDB" }, status: :bad_gateway
  end
end
