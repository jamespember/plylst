class RecentlyStreamedWorker
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find user_id

    if user.active?
      connection = user.settings.to_hash
      spotify = RSpotify::User.new(connection)

      begin
        recent_tracks = spotify.recently_played(limit: 50)
      rescue RestClient::Unauthorized => e
        # Deactivate user if we don't have the right permissions
        user.update_attribute(:active, false)
      end

      if recent_tracks.present?
        recent_track_ids = Array.new

        recent_tracks.each do |track|
          recent_track_ids.push([track.id, track.played_at])
        end

        SaveTracksWorker.perform_async(user.id, recent_track_ids, 'streamed')
      end
    end
  end
end