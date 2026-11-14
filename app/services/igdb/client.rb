module Igdb
  class Client
    BASE_URL = "https://api.igdb.com/v4".freeze
    GENRE_CACHE_KEY   = "igdb/genres/v1".freeze
    MULTIQUERY_LIMIT  = 10 # IGDB allows max 10 queries per multiquery request

    class ApiError < StandardError
      attr_reader :status
      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    FIELDS = %w[
      name summary first_release_date total_rating
      cover.image_id genres.name platforms.name platforms.platform_family.name platforms.platform_family.slug
    ].join(", ").freeze

    # Returns { count:, results: [...], has_more: bool }
    def games(search: nil, genre: nil, page: 1, limit: 24)
      page     = [ page.to_i, 1 ].max
      limit    = limit.to_i.clamp(1, 50)
      offset   = (page - 1) * limit
      genre_id = genre.to_i.positive? ? genre.to_i : nil # ignore junk input

      conditions = []
      conditions << "genres = (#{genre_id})" if genre_id
      conditions << "cover != null & total_rating_count > 5" if search.blank?

      lines = []
      lines << %(search "#{sanitize(search)}";) if search.present?
      lines << "fields #{FIELDS};"
      lines << "where #{conditions.join(' & ')};" if conditions.any?
      # IGDB does not allow `sort` together with `search`
      lines << "sort total_rating_count desc;" if search.blank?
      lines << "limit #{limit + 1};"
      lines << "offset #{offset};"

      rows = post("games", lines.join(" "))
      { count: rows.size, results: rows.first(limit).map { |g| serialize(g) }, has_more: rows.size > limit }
    end

    # Returns { count:, results: [{ id:, name:, slug:, image_url: }] }
    def genres
      Rails.cache.fetch(GENRE_CACHE_KEY, expires_in: 1.month) do
        rows   = post("genres", "fields name, slug; sort name asc; limit 50;")
        images = genre_images(rows.map { |g| g["id"] })

        results = rows.map do |g|
          { id: g["id"], name: g["name"], slug: g["slug"], image_background: images[g["id"]] }
        end

        { count: results.size, results: results }
      end
    end

    private

    def post(endpoint, body, retried: false)
      response = Faraday.post("#{BASE_URL}/#{endpoint}") do |req|
        req.headers["Client-ID"]     = TokenManager.client_id
        req.headers["Authorization"] = "Bearer #{TokenManager.token}"
        req.headers["Content-Type"]  = "text/plain"
        req.body = body
      end

      case response.status
      when 200..299
        JSON.parse(response.body)
      when 401
        raise ApiError.new("IGDB unauthorized", 401) if retried
        TokenManager.invalidate!
        post(endpoint, body, retried: true) # retry once with a fresh token
      when 429
        raise ApiError.new("IGDB rate limit hit, try again shortly", 429)
      else
        raise ApiError.new("IGDB error: #{response.body}", response.status)
      end
    end

    def serialize(game)
      platforms = game["platforms"] || []

      {
        id:        game["id"],
        name:      game["name"],
        summary:   game["summary"],
        metacritic:    game["total_rating"]&.round,
        year:      game["first_release_date"] && Time.at(game["first_release_date"]).utc.year,
        background_image: game.dig("cover", "image_id") &&
          "https://images.igdb.com/igdb/image/upload/t_cover_big/#{game.dig('cover', 'image_id')}.jpg",
        genres:    (game["genres"] || []).map { |g| g["name"] },
        platforms: platforms.map { |p| p["name"] },
        parent_platforms: parent_platforms(platforms)
      }
    end

    def parent_platforms(platforms)
      slug_fallbacks = {
        "PC (Microsoft Windows)" => "pc",
        "Mac" => "mac",
        "iOS" => "ios"
      }

      Array(platforms)                      # nil -> [], so a game with no platforms is safe
        .compact                            # drop any nil entries
        .map do |platform|
        family = platform["platform_family"]
        family.is_a?(Hash) ? family : platform   # fall back to the platform itself
      end
        .uniq { |item| item["slug"] || item["id"] }
        .map  { |item| { id: item["id"], name: item["name"], slug: item["slug"].presence || slug_fallbacks[item["name"]] } }
    end

    # Prevent breaking out of the quoted Apicalypse search string
    def sanitize(text)
      text.to_s.gsub(/["\\;]/, "").strip.first(100)
    end

    # { genre_id => image_url } using the top-rated game of each genre
    def genre_images(genre_ids)
      images = {}

      genre_ids.each_slice(MULTIQUERY_LIMIT).with_index do |ids, i|
        sleep(0.3) if i.positive? # stay under IGDB's 4 requests/second

        body = ids.map do |id|
          <<~Q
        query games "g#{id}" {
          fields cover.image_id, screenshots.image_id;
          where genres = (#{id}) & cover != null & total_rating_count > 50;
          sort total_rating_count desc;
          limit 1;
        };
      Q
        end.join("\n")

        post("multiquery", body).each do |entry|
          id   = entry["name"].delete_prefix("g").to_i
          game = entry["result"]&.first
          images[id] = game && genre_image_url(game)
        end
      end

      images
    end

    def genre_image_url(game)
      if (shot = game.dig("screenshots", 0, "image_id"))
        "https://images.igdb.com/igdb/image/upload/t_screenshot_big/#{shot}.jpg"
      elsif (cover = game.dig("cover", "image_id"))
        "https://images.igdb.com/igdb/image/upload/t_cover_big/#{cover}.jpg"
      end
    end
  end
end
