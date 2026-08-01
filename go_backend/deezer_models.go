package gobackend

import (
	"fmt"
	"strings"
)

type deezerTrack struct {
	ID                    int64             `json:"id"`
	Title                 string            `json:"title"`
	Duration              int               `json:"duration"`
	TrackPosition         int               `json:"track_position"`
	DiskNumber            int               `json:"disk_number"`
	ISRC                  string            `json:"isrc"`
	Link                  string            `json:"link"`
	ReleaseDate           string            `json:"release_date"`
	ExplicitLyrics        bool              `json:"explicit_lyrics"`
	ExplicitContentLyrics int               `json:"explicit_content_lyrics"`
	Artist                deezerArtist      `json:"artist"`
	Album                 deezerAlbumSimple `json:"album"`
	Contributors          []deezerArtist    `json:"contributors"`
}

// deezerTrackIsExplicit maps Deezer's parental-advisory fields to a boolean:
// explicit_lyrics is the boolean flag, explicit_content_lyrics uses 1 to mean
// explicit (0 = clean, 2 = unknown).
func deezerTrackIsExplicit(track deezerTrack) bool {
	return track.ExplicitLyrics || track.ExplicitContentLyrics == 1
}

type deezerArtist struct {
	ID            int64  `json:"id"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
	PictureMedium string `json:"picture_medium"`
	PictureBig    string `json:"picture_big"`
	PictureXL     string `json:"picture_xl"`
	NbFan         int    `json:"nb_fan"`
}

type deezerAlbumSimple struct {
	ID          int64  `json:"id"`
	Title       string `json:"title"`
	Cover       string `json:"cover"`
	CoverMedium string `json:"cover_medium"`
	CoverBig    string `json:"cover_big"`
	CoverXL     string `json:"cover_xl"`
	ReleaseDate string `json:"release_date"`
	RecordType  string `json:"record_type"`
}

// deezerTrackArtistDisplay returns the display artist string for a track,
// preferring the Contributors list (comma-joined) when available, falling
// back to the primary Artist.Name.
func deezerTrackArtistDisplay(track deezerTrack) string {
	if len(track.Contributors) > 0 {
		names := make([]string, len(track.Contributors))
		for i, a := range track.Contributors {
			names[i] = a.Name
		}
		return strings.Join(names, ", ")
	}
	return track.Artist.Name
}

func (c *DeezerClient) convertTrack(track deezerTrack) TrackMetadata {
	artistName := deezerTrackArtistDisplay(track)

	albumImage := track.Album.CoverXL
	if albumImage == "" {
		albumImage = track.Album.CoverBig
	}
	if albumImage == "" {
		albumImage = track.Album.CoverMedium
	}
	if albumImage == "" {
		albumImage = track.Album.Cover
	}

	releaseDate := track.ReleaseDate
	if releaseDate == "" {
		releaseDate = track.Album.ReleaseDate
	}

	return TrackMetadata{
		SpotifyID:   fmt.Sprintf("deezer:%d", track.ID),
		Artists:     artistName,
		Name:        track.Title,
		AlbumName:   track.Album.Title,
		AlbumArtist: track.Artist.Name,
		DurationMS:  track.Duration * 1000,
		Images:      albumImage,
		ReleaseDate: releaseDate,
		TrackNumber: track.TrackPosition,
		DiscNumber:  track.DiskNumber,
		ExternalURL: track.Link,
		ISRC:        track.ISRC,
		AlbumID:     fmt.Sprintf("deezer:%d", track.Album.ID),
		ArtistID:    fmt.Sprintf("deezer:%d", track.Artist.ID),
		Explicit:    deezerTrackIsExplicit(track),
	}
}

type deezerGenre struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type deezerAlbumFull struct {
	ID          int64  `json:"id"`
	Title       string `json:"title"`
	Cover       string `json:"cover"`
	CoverMedium string `json:"cover_medium"`
	CoverBig    string `json:"cover_big"`
	CoverXL     string `json:"cover_xl"`
	ReleaseDate string `json:"release_date"`
	NbTracks    int    `json:"nb_tracks"`
	RecordType  string `json:"record_type"`
	Label       string `json:"label"`
	Copyright   string `json:"copyright"`
	Genres      struct {
		Data []deezerGenre `json:"data"`
	} `json:"genres"`
	Artist       deezerArtist   `json:"artist"`
	Contributors []deezerArtist `json:"contributors"`
	Tracks       struct {
		Data []deezerTrack `json:"data"`
	} `json:"tracks"`
}

type deezerArtistFull struct {
	ID            int64  `json:"id"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
	PictureMedium string `json:"picture_medium"`
	PictureBig    string `json:"picture_big"`
	PictureXL     string `json:"picture_xl"`
	NbFan         int    `json:"nb_fan"`
	NbAlbum       int    `json:"nb_album"`
}

type deezerPlaylistFull struct {
	ID            int64  `json:"id"`
	Title         string `json:"title"`
	Picture       string `json:"picture"`
	PictureMedium string `json:"picture_medium"`
	PictureBig    string `json:"picture_big"`
	PictureXL     string `json:"picture_xl"`
	NbTracks      int    `json:"nb_tracks"`
	Creator       struct {
		Name string `json:"name"`
	} `json:"creator"`
	Tracks struct {
		Data []deezerTrack `json:"data"`
	} `json:"tracks"`
}

func (c *DeezerClient) getBestArtistImage(artist deezerArtist) string {
	if artist.PictureXL != "" {
		return artist.PictureXL
	}
	if artist.PictureBig != "" {
		return artist.PictureBig
	}
	if artist.PictureMedium != "" {
		return artist.PictureMedium
	}
	return artist.Picture
}

func (c *DeezerClient) getBestArtistImageFull(artist deezerArtistFull) string {
	if artist.PictureXL != "" {
		return artist.PictureXL
	}
	if artist.PictureBig != "" {
		return artist.PictureBig
	}
	if artist.PictureMedium != "" {
		return artist.PictureMedium
	}
	return artist.Picture
}

func (c *DeezerClient) getBestAlbumImage(album deezerAlbumFull) string {
	if album.CoverXL != "" {
		return album.CoverXL
	}
	if album.CoverBig != "" {
		return album.CoverBig
	}
	if album.CoverMedium != "" {
		return album.CoverMedium
	}
	return album.Cover
}
