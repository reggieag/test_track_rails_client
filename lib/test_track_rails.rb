require "test_track_rails/engine"
require 'public_suffix'

module TestTrackRails
  module_function

  def update_config
    yield(ConfigUpdater.new)
  end

  def cookie_domain(host)
    "." + PublicSuffix.parse(host).domain
  end

  def url
    return nil unless private_url
    full_uri = URI.parse(private_url)
    full_uri.user = nil
    full_uri.password = nil
    full_uri.to_s
  end

  def private_url
    ENV['TEST_TRACK_API_URL']
  end
end
