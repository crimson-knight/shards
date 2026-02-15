module DemoAnalytics
  VERSION = "0.1.0"

  # Returns sample analytics data for the given metric.
  def self.query(metric : String) : String
    case metric
    when "page_views"
      "page_views=42831 (+12.5% wow)"
    when "users"
      "active_users=1247 sessions=3891"
    when "events"
      "events=156302 unique=23447"
    else
      "metric=#{metric} value=100 (sample)"
    end
  end
end
