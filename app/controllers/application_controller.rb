class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Include performance monitoring concerns
  include PerformanceMonitoring
  include QueryCounter

  # Skip CSRF protection for API endpoints
  skip_before_action :verify_authenticity_token, if: -> { request.path.start_with?("/api/") }

  # Enable CORS for API endpoints
  before_action :set_cors_headers, if: -> { request.path.start_with?("/api/") }

  # Cache control headers for API responses
  after_action :set_cache_control_headers, if: -> { request.path.start_with?("/api/") }

  private

  def set_cors_headers
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Origin, Content-Type, Accept, Authorization, Token"
    response.headers["Access-Control-Max-Age"] = "1728000"
  end

  def set_cache_control_headers
    # Set appropriate cache headers based on the response
    if response.status == 200 && request.get?
      response.headers["Cache-Control"] = "public, max-age=300" # 5 minutes default
      response.headers["Vary"] = "Accept, Authorization"
    else
      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    end
  end
end
