module Igdb
  class TokenManager
    TOKEN_URL     = "https://id.twitch.tv/oauth2/token".freeze
    EXPIRY_BUFFER = 5.minutes # refresh a bit early

    class AuthError < StandardError; end

    @mutex      = Mutex.new
    @token      = nil
    @expires_at = nil

    class << self
      # Returns a valid token, fetching a new one only when needed.
      def token
        @mutex.synchronize do
          refresh! if @token.nil? || Time.current >= @expires_at
          @token
        end
      end

      # Call when IGDB answers 401 so the next call fetches a fresh token.
      def invalidate!
        @mutex.synchronize do
          @token = nil
          @expires_at = nil
        end
      end

      def client_id
        ENV.fetch("TWITCH_CLIENT_ID")
      end

      private

      def refresh!
        response = Faraday.post(TOKEN_URL, {
          client_id:     client_id,
          client_secret: ENV.fetch("TWITCH_CLIENT_SECRET"),
          grant_type:    "client_credentials"
        })

        raise AuthError, "Twitch auth failed (#{response.status}): #{response.body}" unless response.success?

        data        = JSON.parse(response.body)
        @token      = data.fetch("access_token")
        @expires_at = Time.current + data.fetch("expires_in").to_i.seconds - EXPIRY_BUFFER
      end
    end
  end
end