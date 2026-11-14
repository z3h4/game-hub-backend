class GamesController < ApplicationController
  def index
    result = Igdb::Client.new.games(
      search: params[:q],
      genre:  params[:genre],
      page:   params[:page] || 1,
      limit:  params[:limit] || 24
    )
    render json: result
  end
end
