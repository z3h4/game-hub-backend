class GamesController < ApplicationController
  def index
    result = Igdb::Client.new.games(
      search:          params[:search],
      genre:           params[:genre],
      platforms:       params[:platforms],
      platform_family: params[:platform_family],
      ordering:        params[:ordering],
      page:            params[:page] || 1,
      limit:           params[:limit] || 24
    )
    render json: result
  end
end
