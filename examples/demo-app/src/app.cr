require "demo_analytics"

puts "Demo App — using demo_analytics v#{DemoAnalytics::VERSION}"
puts
puts "Page views: #{DemoAnalytics.query("page_views")}"
puts "Users:      #{DemoAnalytics.query("users")}"
puts "Events:     #{DemoAnalytics.query("events")}"
