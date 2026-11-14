# frozen_string_literal: true

class GenresController < ApplicationController
  def index
    render json: Igdb::Client.new.genres
  end
end
