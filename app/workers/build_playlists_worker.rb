class BuildPlaylistsWorker
  include Sidekiq::Worker
  include ApplicationHelper
  sidekiq_options queue: 'critical'

  def perform(user_id)
    user = User.find user_id

    if user.active?
      connection = user.settings.to_hash
      spotify = RSpotify::User.new(connection)

      begin
        spotify_playlists = spotify.playlists(limit:50)
      rescue RestClient::NotFound => e
      end

      user.playlists.find_each do |playlist|

        if spotify_playlists.present?
          existing_playlist = spotify_playlists.select{|key| key.name == "PLYLST: #{playlist.name}"}
        else
          existing_playlist = nil
        end

        if existing_playlist.present?
          existing_playlist = RSpotify::Playlist.find(spotify.id, existing_playlist.first.id)

          # Thanks to Spotify API limits, we need to divide the remove_tracks! call in to groups of 100
          total = existing_playlist.total
          times_to_loop = (total.to_f / 100).ceil

          times_to_loop.times { existing_playlist.remove_tracks!(existing_playlist.tracks) }
          existing_playlist.change_details!(description: "Created with PLYLST.app!")
        else
          existing_playlist = spotify.create_playlist!("PLYLST: #{playlist.name}")
        end

        tracks = playlist.filtered_tracks(user).pluck(:spotify_id)
        tracks_formatted = tracks.map{|x| x.prepend('spotify:track:')}

        # Divide tracks in to groups of 100, due to Spotify API limit
        tracks_formatted.each_slice(100) do |group|
          existing_playlist.add_tracks!(group)
        end
      end
    end
  end
end
