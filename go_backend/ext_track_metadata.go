package gobackend

// ExtTrackMetadata is the Go-side mirror of the track object every JS extension
// returns from searchTracks / customSearch.
//
// Naming convention: Go fields are PascalCase; JSON tags match the snake_case
// keys the JS extensions actually emit.
//
// ── Core identity ──────────────────────────────────────────────────────────
//   id            bare or prefixed ID for the track itself  ("deezer:123")
//   name / title  track title (extensions use either key)
//   artists       primary artist string, comma-separated
//   album_name    album the track belongs to
//   album_artist  album-level artist (may differ from track artist)
//
// ── Collection IDs (used by cross-extension share) ─────────────────────────
//   album_id      ID of the parent album  ("tidal:456", "MPREb_…", bare ASIN, …)
//   artist_id     ID of the primary artist ("deezer:789", "UC…", numeric SC id, …)
//   album_url     Full album URL when the extension provides it directly.
//                 Spotify puts "https://open.spotify.com/album/{id}" here.
//                 Apple Music puts just the numeric catalog ID here.
//   external_urls Canonical URL for the track itself (SoundCloud permalink, etc.)
//
// ── Provider-specific IDs (legacy, kept for backwards compat) ──────────────
//   tidal_id / qobuz_id / deezer_id / spotify_id
//   These were previously used by resolveCollectionItemID, but that function
//   now delegates to buildAlbumURL / buildArtistURL which use album_id /
//   artist_id instead, so these fields are no longer on the hot path.
type ExtTrackMetadata struct {
	// Core
	ID          string `json:"id"`
	Name        string `json:"name"`
	Title       string `json:"title"`   // some extensions use "title" instead of "name"
	Artists     string `json:"artists"` // comma-separated primary artist(s)
	AlbumName   string `json:"album_name"`
	AlbumArtist string `json:"album_artist"`
	DurationMS  int    `json:"duration_ms"`
	TrackNumber int    `json:"track_number"`
	ISRC        string `json:"isrc"`
	CoverURL    string `json:"cover_url"`
	ReleaseDate string `json:"release_date"`
	ItemType    string `json:"item_type"`

	// Collection IDs — the fields cross_extension_share.go needs.
	AlbumID      string `json:"album_id"`
	ArtistID     string `json:"artist_id"`
	AlbumURL     string `json:"album_url"`     // full URL or bare catalog ID depending on extension
	ExternalURLs string `json:"external_urls"` // canonical track permalink (SoundCloud, Apple, …)

	// Provider-specific IDs (legacy / enrichment use)
	TidalID   string `json:"tidal_id"`
	QobuzID   string `json:"qobuz_id"`
	DeezerID  string `json:"deezer_id"`
	SpotifyID string `json:"spotify_id"`
}
