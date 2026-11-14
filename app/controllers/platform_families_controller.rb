# frozen_string_literal: true

class PlatformFamiliesController < ApplicationController
  def index
    render json: Igdb::Client.new.platform_families
  end

  def show
    family = Igdb::Client.new.platform_family(params[:id])
    return render json: { error: "Platform family not found" }, status: :not_found unless family

    render json: family
  end
end
