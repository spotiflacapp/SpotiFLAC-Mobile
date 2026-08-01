package gobackend

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// attemptExtensionDownload runs a single provider.Download attempt: builds the
// output path, reports progress, and on success assembles the full
// DownloadResponse (overlay, request fallbacks, optional title/artist/composer
// fallback, metadata embed, ISRC index). On failure it writes into
// lastErr/lastErrType/lastRetryAfterSeconds exactly as the inline code did
// (leaving them untouched when neither branch applies) so callers can keep
// their own verification_required/stop-fallback handling and error messages.
// cancelledOuter true means the caller must return (nil, ErrDownloadCancelled).
func attemptExtensionDownload(
	req DownloadRequest,
	ext *loadedExtension,
	provider *extensionProviderWrapper,
	trackID, quality, providerLabel string,
	applyTitleFallback bool,
	lastErr *error,
	lastErrType *string,
	lastRetryAfterSeconds *int,
) (resp *DownloadResponse, cancelledOuter bool) {
	outputPath := buildOutputPathForExtension(req, ext)
	if shouldReuseExistingOutput(req, outputPath) {
		result := DownloadResult{FilePath: outputPath}
		enrichResultQualityFromFile(&result)
		built := buildDownloadSuccessResponse(
			req,
			result,
			providerLabel,
			"File already exists",
			outputPath,
			true,
		)
		if req.ItemID != "" {
			CompleteItemProgress(req.ItemID)
		}
		GoLog("[DownloadWithExtensionFallback] Keeping existing output instead of replacing it: %s\n", outputPath)
		return &built, false
	}
	if req.ItemID != "" {
		SetItemPreparingStage(req.ItemID, "resolving_stream")
	}

	result, err := provider.Download(trackID, quality, outputPath, req.ItemID, func(percent int) {
		if req.ItemID != "" {
			normalized := float64(percent) / 100.0
			if normalized < 0 {
				normalized = 0
			}
			if normalized > 1 {
				normalized = 1
			}
			SetItemProgress(req.ItemID, normalized, 0, 0)
		}
	})
	downloadSucceeded := err == nil && result != nil && result.Success
	if downloadSucceeded {
		resolved := resolvedTrackInfo{
			Title:      result.Title,
			ArtistName: result.Artist,
			AlbumName:  result.Album,
			ISRC:       result.ISRC,
			Duration:   result.DurationMS / 1000,
			SkipNameVerification: strings.EqualFold(strings.TrimSpace(req.Source), strings.TrimSpace(providerLabel)) ||
				ext.Manifest.HasCustomMatching(),
		}
		if !trackMatchesRequest(req, resolved, "Extension "+providerLabel) {
			discardRejectedExtensionOutput(result, outputPath)
			*lastErr = fmt.Errorf("provider %s returned a different track", providerLabel)
			*lastErrType = "not_found"
			return nil, false
		}
	}
	if req.ItemID != "" && downloadSucceeded {
		SetItemFinalizing(req.ItemID)
	}
	if shouldAbortCancelledFallback(req.ItemID, err) {
		return nil, true
	}

	if downloadSucceeded {
		metadataStartedAt := time.Now()
		enrichRequestExtendedMetadata(&req)
		LogDebug(
			"DownloadPipeline",
			"item=%s provider=%s post-transfer metadataMs=%.1f",
			req.ItemID,
			providerLabel,
			extensionDurationMs(time.Since(metadataStartedAt)),
		)

		normalizedResult, alreadyExists := normalizeExtensionDownloadResult(result)
		message := "Downloaded from " + providerLabel
		if alreadyExists {
			message = "File already exists"
		}

		built := buildDownloadSuccessResponse(
			req,
			normalizedResult,
			providerLabel,
			message,
			normalizedResult.FilePath,
			alreadyExists,
		)
		overlayExtensionDownloadMetadata(&built, result)
		if ext.Manifest.SkipMetadataEnrichment {
			built.SkipMetadataEnrichment = true
		}
		applyExtensionRequestFallbacks(&built, req)

		if applyTitleFallback {
			if req.TrackName != "" && built.Title == "" {
				built.Title = req.TrackName
			}
			if req.ArtistName != "" && built.Artist == "" {
				built.Artist = req.ArtistName
			}
			if req.Composer != "" && built.Composer == "" {
				built.Composer = req.Composer
			}
		}

		embedExtensionDownloadMetadata(built, req, alreadyExists)

		if !alreadyExists && !isFDOutput(req.OutputFD) && strings.TrimSpace(req.OutputDir) != "" {
			indexISRC := strings.TrimSpace(built.ISRC)
			if indexISRC == "" {
				indexISRC = strings.TrimSpace(req.ISRC)
			}
			if indexISRC != "" && strings.TrimSpace(built.FilePath) != "" {
				AddToISRCIndex(req.OutputDir, indexISRC, built.FilePath)
			}
		}

		if req.ItemID != "" {
			CompleteItemProgress(req.ItemID)
		}
		return &built, false
	}

	if err != nil {
		if errors.Is(err, ErrDownloadCancelled) {
			return &DownloadResponse{
				Success:   false,
				Error:     "Download cancelled",
				ErrorType: "cancelled",
				Service:   providerLabel,
			}, false
		}
		*lastErr = err
		*lastErrType = ""
	} else if result != nil && result.ErrorMessage != "" {
		*lastErr = fmt.Errorf("%s", result.ErrorMessage)
		*lastErrType = normalizeExtensionDownloadErrorType(result.ErrorType, result.ErrorMessage)
		*lastRetryAfterSeconds = result.RetryAfterSeconds
	} else if result == nil {
		*lastErr = fmt.Errorf("extension returned no download result")
		*lastErrType = "extension_error"
	}
	return nil, false
}

// attemptVerifiedResumeBeforeMetadata gives a just-verified request one direct
// chance against its selected provider before optional metadata providers run.
// Download-provider sources keep their normal precedence because they may
// dynamically lock fallback from checkAvailability.
func attemptVerifiedResumeBeforeMetadata(
	req DownloadRequest,
	selectedProvider string,
	extManager *extensionManager,
) (*DownloadResponse, bool) {
	selectedProvider = strings.TrimSpace(selectedProvider)
	if selectedProvider == "" || extManager == nil {
		return nil, false
	}

	sourceProvider := strings.TrimSpace(req.Source)
	if sourceProvider != "" && !strings.EqualFold(sourceProvider, selectedProvider) {
		if sourceExt, err := extManager.GetExtension(sourceProvider); err == nil &&
			sourceExt != nil && sourceExt.Enabled && sourceExt.Error == "" &&
			sourceExt.Manifest != nil && sourceExt.Manifest.IsDownloadProvider() {
			return nil, false
		}
	}

	ext, err := extManager.GetExtension(selectedProvider)
	if err != nil || ext == nil || !ext.Enabled || ext.Error != "" ||
		ext.Manifest == nil || !ext.Manifest.IsDownloadProvider() {
		return nil, false
	}

	provider := newExtensionProviderWrapper(ext)
	var availability *ExtAvailabilityResult
	trackID := ""
	if strings.EqualFold(sourceProvider, selectedProvider) {
		trackID = resolvePreferredTrackIDForExtension(ext, req, "")
	} else {
		availability, err = provider.CheckAvailabilityForItemID(
			req.ISRC,
			req.TrackName,
			req.ArtistName,
			req.SpotifyID,
			req.DeezerID,
			req.TidalID,
			req.QobuzID,
			req.DurationMS,
			req.ItemID,
		)
		if shouldAbortCancelledFallback(req.ItemID, err) {
			return nil, true
		}
		if err != nil {
			if strings.EqualFold(classifyDownloadErrorType(err.Error()), "verification_required") {
				return &DownloadResponse{
					Success:   false,
					Error:     "Download failed: " + err.Error(),
					ErrorType: "verification_required",
					Service:   selectedProvider,
				}, false
			}
			return nil, false
		}
		if availability == nil || !availability.Available {
			if shouldStopProviderFallback(availability) {
				return buildExtensionFallbackStoppedResponse(selectedProvider, availability, nil), false
			}
			return nil, false
		}
		trackID = resolvePreferredTrackIDForExtension(ext, req, availability.TrackID)
	}

	var lastErr error
	var lastErrType string
	var lastRetryAfterSeconds int
	resp, cancelled := attemptExtensionDownload(
		req,
		ext,
		provider,
		trackID,
		req.Quality,
		selectedProvider,
		strings.EqualFold(sourceProvider, selectedProvider),
		&lastErr,
		&lastErrType,
		&lastRetryAfterSeconds,
	)
	if cancelled || resp != nil {
		return resp, cancelled
	}

	errorType := lastErrType
	if errorType == "" && lastErr != nil {
		errorType = classifyDownloadErrorType(lastErr.Error())
	}
	if strings.EqualFold(errorType, "verification_required") {
		errorMessage := "Verification required"
		if lastErr != nil {
			errorMessage = "Download failed: " + lastErr.Error()
		}
		return &DownloadResponse{
			Success:           false,
			Error:             errorMessage,
			ErrorType:         "verification_required",
			RetryAfterSeconds: lastRetryAfterSeconds,
			Service:           selectedProvider,
		}, false
	}
	if lastErr != nil && isOutputStorageWriteFailure(errorType, lastErr.Error()) {
		return buildOutputStorageFailureResponse(
			selectedProvider,
			lastErr,
			lastRetryAfterSeconds,
		), false
	}
	// A failed fast attempt may still succeed after source enrichment resolves a
	// better provider-native ID. The normal path below retains strict/stop-
	// fallback semantics for that prepared retry.
	return nil, false
}

func buildOutputStorageFailureResponse(
	providerID string,
	err error,
	retryAfterSeconds int,
) *DownloadResponse {
	message := "Output storage is not writable"
	if err != nil {
		message = err.Error()
	}
	return &DownloadResponse{
		Success:           false,
		Error:             "Download failed: " + message,
		ErrorType:         "permission",
		RetryAfterSeconds: retryAfterSeconds,
		Service:           providerID,
	}
}

func DownloadWithExtensionFallback(req DownloadRequest) (*DownloadResponse, error) {
	pipelineStartedAt := time.Now()
	defer func() {
		LogDebug(
			"DownloadPipeline",
			"item=%s service=%s totalMs=%.1f",
			req.ItemID,
			req.Service,
			extensionDurationMs(time.Since(pipelineStartedAt)),
		)
	}()
	preparationKey := downloadPreparationKey(req)
	metadataPrepared := false
	resumedAfterVerification := false
	if prepared, preparedMetadata, ok := takePreparedDownloadRequest(preparationKey, req); ok {
		req = prepared
		metadataPrepared = preparedMetadata
		resumedAfterVerification = true
		GoLog("[DownloadWithExtensionFallback] Resuming item %s after verification (metadata prepared: %v)\n", req.ItemID, metadataPrepared)
	}
	if req.ItemID != "" {
		StartItemProgress(req.ItemID)
		SetItemPreparingStage(req.ItemID, "resolving_metadata")
	}

	priority := GetProviderPriority()
	extManager := getExtensionManager()
	strictMode := !req.UseFallback
	selectedProvider := strings.TrimSpace(req.Service)

	if isDownloadCancelled(req.ItemID) {
		return nil, ErrDownloadCancelled
	}

	if strictMode {
		if selectedProvider == "" {
			selectedProvider = strings.TrimSpace(req.Source)
		}
		if selectedProvider != "" {
			priority = []string{selectedProvider}
			GoLog("[DownloadWithExtensionFallback] Strict mode enabled, provider locked to: %s\n", selectedProvider)
		}
	}

	if !strictMode && req.Service != "" {
		found := false
		for _, p := range priority {
			if strings.EqualFold(p, req.Service) {
				found = true
				break
			}
		}
		newPriority := []string{req.Service}
		for _, p := range priority {
			if !strings.EqualFold(p, req.Service) {
				newPriority = append(newPriority, p)
			}
		}
		priority = newPriority
		if !found {
			GoLog("[DownloadWithExtensionFallback] Extension service '%s' added to priority front\n", req.Service)
		} else {
			GoLog("[DownloadWithExtensionFallback] Extension service '%s' moved to priority front\n", req.Service)
		}
		GoLog("[DownloadWithExtensionFallback] New priority order: %v\n", priority)
	}

	var lastErr error
	var lastErrType string
	var lastRetryAfterSeconds int
	var stopProviderFallback bool
	var sourceExtensionLocked bool
	var sourceExtensionAvailability *ExtAvailabilityResult
	var sourceExtensionTrackID string

	if resumedAfterVerification && !metadataPrepared {
		GoLog("[DownloadWithExtensionFallback] Trying verified provider %s before optional metadata enrichment\n", selectedProvider)
		resp, cancelled := attemptVerifiedResumeBeforeMetadata(req, selectedProvider, extManager)
		if cancelled {
			return nil, ErrDownloadCancelled
		}
		if resp != nil {
			return resp, nil
		}
		if req.ItemID != "" {
			SetItemPreparingStage(req.ItemID, "resolving_metadata")
		}
	}

	if req.Source != "" && selectedProvider != req.Source {
		ext, err := extManager.GetExtension(req.Source)
		if err == nil && ext.Enabled && ext.Error == "" && ext.Manifest.IsDownloadProvider() {
			provider := newExtensionProviderWrapper(ext)
			availability, availErr := provider.CheckAvailabilityForItemID(req.ISRC, req.TrackName, req.ArtistName, req.SpotifyID, req.DeezerID, req.TidalID, req.QobuzID, req.DurationMS, req.ItemID)
			if shouldAbortCancelledFallback(req.ItemID, availErr) {
				return nil, ErrDownloadCancelled
			}
			if availErr != nil {
				GoLog("[DownloadWithExtensionFallback] Source extension %s preflight failed (non-fatal): %v\n", req.Source, availErr)
			} else if shouldStopProviderFallback(availability) {
				sourceExtensionLocked = true
				sourceExtensionAvailability = availability
				sourceExtensionTrackID = strings.TrimSpace(availability.TrackID)
				selectedProvider = req.Source
				GoLog("[DownloadWithExtensionFallback] Source extension %s requested skip_fallback (available=%v), locking download to source extension\n", req.Source, availability.Available)
			}
		}
	}

	if !metadataPrepared {
		if req.Source != "" {
			ext, err := extManager.GetExtension(req.Source)
			if err == nil && ext.Enabled && ext.Error == "" && ext.Manifest.IsMetadataProvider() {
				GoLog("[DownloadWithExtensionFallback] Enriching track from extension '%s'...\n", req.Source)

				provider := newExtensionProviderWrapper(ext)
				trackMeta := &ExtTrackMetadata{
					ID:          req.SpotifyID,
					Name:        req.TrackName,
					Artists:     req.ArtistName,
					AlbumName:   req.AlbumName,
					DurationMS:  req.DurationMS,
					ISRC:        req.ISRC,
					ReleaseDate: req.ReleaseDate,
					TrackNumber: req.TrackNumber,
					TotalTracks: req.TotalTracks,
					DiscNumber:  req.DiscNumber,
					TotalDiscs:  req.TotalDiscs,
					ProviderID:  req.Source,
					Composer:    req.Composer,
				}

				enrichedTrack, err := provider.EnrichTrackForItemID(trackMeta, req.ItemID)
				if shouldAbortCancelledFallback(req.ItemID, err) {
					return nil, ErrDownloadCancelled
				}
				if err == nil && enrichedTrack != nil {
					if enrichedTrack.ISRC != "" && enrichedTrack.ISRC != req.ISRC {
						GoLog("[DownloadWithExtensionFallback] ISRC enriched: %s -> %s\n", req.ISRC, enrichedTrack.ISRC)
						req.ISRC = enrichedTrack.ISRC
					}
					if enrichedTrack.TidalID != "" {
						GoLog("[DownloadWithExtensionFallback] Tidal ID from Odesli: %s\n", enrichedTrack.TidalID)
						req.TidalID = enrichedTrack.TidalID
					}
					if enrichedTrack.QobuzID != "" {
						GoLog("[DownloadWithExtensionFallback] Qobuz ID from Odesli: %s\n", enrichedTrack.QobuzID)
						req.QobuzID = enrichedTrack.QobuzID
					}
					if enrichedTrack.DeezerID != "" {
						GoLog("[DownloadWithExtensionFallback] Deezer ID from Odesli: %s\n", enrichedTrack.DeezerID)
						req.DeezerID = enrichedTrack.DeezerID
					}
					if enrichedTrack.Name != "" {
						req.TrackName = enrichedTrack.Name
					}
					if enrichedTrack.Artists != "" {
						req.ArtistName = enrichedTrack.Artists
					}
					overlayStr(&req.AlbumName, enrichedTrack.AlbumName, "AlbumName")
					overlayStr(&req.AlbumArtist, enrichedTrack.AlbumArtist, "")
					overlayInt(&req.DurationMS, enrichedTrack.DurationMS, "DurationMS")
					overlayStr(&req.CoverURL, enrichedTrack.CoverURL, "")
					overlayStr(&req.SpotifyID, enrichedTrack.ID, "Track ID")
					overlayStr(&req.Label, enrichedTrack.Label, "Label")
					overlayStr(&req.Copyright, enrichedTrack.Copyright, "Copyright")
					overlayStr(&req.Genre, enrichedTrack.Genre, "Genre")
					overlayStr(&req.ReleaseDate, enrichedTrack.ReleaseDate, "ReleaseDate")
					overlayInt(&req.TrackNumber, enrichedTrack.TrackNumber, "TrackNumber")
					overlayInt(&req.TotalTracks, enrichedTrack.TotalTracks, "TotalTracks")
					overlayInt(&req.DiscNumber, enrichedTrack.DiscNumber, "DiscNumber")
					overlayInt(&req.TotalDiscs, enrichedTrack.TotalDiscs, "TotalDiscs")
					overlayStr(&req.Composer, enrichedTrack.Composer, "Composer")
				}
			}
		}

		if req.Source != "" &&
			req.TrackName != "" && req.ArtistName != "" &&
			(req.AlbumName == "" || req.ReleaseDate == "" || req.ISRC == "") {

			searchQuery := req.TrackName + " " + req.ArtistName
			GoLog("[DownloadWithExtensionFallback] Metadata incomplete, searching providers for: %s\n", searchQuery)

			// Only the first match is consumed below. Asking for five made the manager
			// continue through additional providers even after it already had a usable
			// match, multiplying the per-provider timeout on slow networks.
			tracks, searchErr := extManager.SearchTracksWithMetadataProvidersForItemID(searchQuery, 1, true, req.ItemID)
			if shouldAbortCancelledFallback(req.ItemID, searchErr) {
				return nil, ErrDownloadCancelled
			}
			if searchErr == nil && len(tracks) > 0 {
				track := tracks[0]
				GoLog("[DownloadWithExtensionFallback] Metadata match (%s): %s - %s (album: %s, date: %s, isrc: %s)\n",
					track.ProviderID, track.Name, track.Artists, track.AlbumName, track.ReleaseDate, track.ISRC)

				overlayStr(&req.AlbumName, track.AlbumName, "")
				overlayStr(&req.AlbumArtist, track.AlbumArtist, "")
				overlayStr(&req.ReleaseDate, track.ReleaseDate, "")
				overlayStr(&req.ISRC, track.ISRC, "")
				overlayInt(&req.TrackNumber, track.TrackNumber, "")
				overlayInt(&req.TotalTracks, track.TotalTracks, "")
				overlayInt(&req.DiscNumber, track.DiscNumber, "")
				overlayInt(&req.TotalDiscs, track.TotalDiscs, "")
				overlayStr(&req.Composer, track.Composer, "")
				overlayStr(&req.CoverURL, track.CoverURL, "")
				overlayStr(&req.Genre, track.Genre, "")
				overlayStr(&req.Label, track.Label, "")
				overlayStr(&req.Copyright, track.Copyright, "")
			} else if searchErr != nil {
				GoLog("[DownloadWithExtensionFallback] Metadata provider search failed (non-fatal): %v\n", searchErr)
			}

		}
	}
	if req.Source != "" && selectedProvider == req.Source {
		if isDownloadCancelled(req.ItemID) {
			return nil, ErrDownloadCancelled
		}

		if sourceExtensionLocked && (sourceExtensionAvailability == nil || !sourceExtensionAvailability.Available) {
			GoLog("[DownloadWithExtensionFallback] Source extension %s stopped fallback before download (reason: %s)\n", req.Source, resolveExtensionAvailabilityReason(sourceExtensionAvailability, nil))
			return buildExtensionFallbackStoppedResponse(req.Source, sourceExtensionAvailability, nil), nil
		}

		GoLog("[DownloadWithExtensionFallback] Track source is extension '%s' matching selected provider, trying it first\n", req.Source)

		ext, err := extManager.GetExtension(req.Source)
		if err == nil && ext.Enabled && ext.Error == "" && ext.Manifest.IsDownloadProvider() {
			stopProviderFallback = ext.Manifest.StopsProviderFallback()

			provider := newExtensionProviderWrapper(ext)

			trackID := resolvePreferredTrackIDForExtension(ext, req, sourceExtensionTrackID)

			GoLog("[DownloadWithExtensionFallback] Downloading from source extension with trackID: %s (stopProviderFallback: %v)\n", trackID, stopProviderFallback)

			resp, cancelledOuter := attemptExtensionDownload(req, ext, provider, trackID, req.Quality, req.Source, true, &lastErr, &lastErrType, &lastRetryAfterSeconds)
			if cancelledOuter {
				return nil, ErrDownloadCancelled
			}
			if resp != nil {
				return resp, nil
			}
			GoLog("[DownloadWithExtensionFallback] Source extension %s failed: %v\n", req.Source, lastErr)

			sourceErrType := lastErrType
			if sourceErrType == "" && lastErr != nil {
				sourceErrType = classifyDownloadErrorType(lastErr.Error())
			}
			if lastErr != nil && isOutputStorageWriteFailure(sourceErrType, lastErr.Error()) {
				GoLog("[DownloadWithExtensionFallback] Source extension %s hit an unwritable output path; stopping provider fallback\n", req.Source)
				return buildOutputStorageFailureResponse(
					req.Source,
					lastErr,
					lastRetryAfterSeconds,
				), nil
			}
			if strings.EqualFold(sourceErrType, "verification_required") {
				GoLog("[DownloadWithExtensionFallback] Source extension %s requires verification, not trying other providers\n", req.Source)
				cachePreparedDownloadRequest(preparationKey, req)
				return &DownloadResponse{
					Success:   false,
					Error:     "Download failed: " + lastErr.Error(),
					ErrorType: "verification_required",
					Service:   req.Source,
				}, nil
			}

			if stopProviderFallback || sourceExtensionLocked {
				if sourceExtensionLocked {
					GoLog("[DownloadWithExtensionFallback] Source extension %s requested skip_fallback, not trying other providers\n", req.Source)
					return buildExtensionFallbackStoppedResponse(req.Source, sourceExtensionAvailability, lastErr), nil
				}
				GoLog("[DownloadWithExtensionFallback] stopProviderFallback is true, not trying other providers\n")
				return &DownloadResponse{
					Success:           false,
					Error:             "Download failed: " + lastErr.Error(),
					ErrorType:         firstNonEmptyTrimmed(lastErrType, "extension_error"),
					RetryAfterSeconds: lastRetryAfterSeconds,
					Service:           req.Source,
				}, nil
			}
		} else {
			GoLog("[DownloadWithExtensionFallback] Source extension %s not available or not a download provider\n", req.Source)
		}
	}

	healthProtectedProvider := selectedProvider
	if strings.TrimSpace(healthProtectedProvider) == "" {
		healthProtectedProvider = req.Source
	}
	priority = prioritizeFallbackProvidersByHealth(priority, extManager, healthProtectedProvider)
	priority = moveProviderToFront(priority, selectedProvider)

	for _, providerID := range priority {
		if isDownloadCancelled(req.ItemID) {
			return nil, ErrDownloadCancelled
		}

		providerID = strings.TrimSpace(providerID)
		if providerID == "" {
			continue
		}
		// Skip the origin extension only when it differs from the explicitly
		// selected provider; otherwise it must still be attempted here.
		if providerID == req.Source && req.Source != selectedProvider {
			continue
		}

		if providerID != selectedProvider && !isExtensionFallbackAllowed(providerID) {
			GoLog("[DownloadWithExtensionFallback] Skipping extension provider %s (not enabled for fallback)\n", providerID)
			continue
		}

		GoLog("[DownloadWithExtensionFallback] Trying provider: %s\n", providerID)

		{
			ext, err := extManager.GetExtension(providerID)
			if err != nil || !ext.Enabled || ext.Error != "" {
				GoLog("[DownloadWithExtensionFallback] Extension %s not available\n", providerID)
				continue
			}

			if !ext.Manifest.IsDownloadProvider() {
				continue
			}

			provider := newExtensionProviderWrapper(ext)

			availability, err := provider.CheckAvailabilityForItemID(req.ISRC, req.TrackName, req.ArtistName, req.SpotifyID, req.DeezerID, req.TidalID, req.QobuzID, req.DurationMS, req.ItemID)
			if shouldAbortCancelledFallback(req.ItemID, err) {
				return nil, ErrDownloadCancelled
			}
			terminalAvailability := shouldStopProviderFallback(availability)
			if err != nil || !availability.Available {
				GoLog("[DownloadWithExtensionFallback] %s: not available\n", providerID)
				if err != nil {
					lastErr = err
					if strings.EqualFold(classifyDownloadErrorType(err.Error()), "verification_required") {
						GoLog("[DownloadWithExtensionFallback] %s requires verification (availability); pausing fallback to open the challenge\n", providerID)
						cachePreparedDownloadRequest(preparationKey, req)
						return &DownloadResponse{
							Success:   false,
							Error:     "Download failed: " + err.Error(),
							ErrorType: "verification_required",
							Service:   providerID,
						}, nil
					}
				}
				if terminalAvailability {
					GoLog("[DownloadWithExtensionFallback] %s requested skip_fallback after availability check\n", providerID)
					return buildExtensionFallbackStoppedResponse(providerID, availability, err), nil
				}
				continue
			}

			req.OutputExt = ""

			// Honor the requested quality when this provider recognizes it
			// (e.g. an explicit user selection). Only when the token is not
			// one of this provider's own options do we fall back to its
			// highest quality, since a source provider's token may not map.
			fallbackQuality := req.Quality
			if len(ext.Manifest.QualityOptions) > 0 {
				requested := strings.TrimSpace(req.Quality)
				recognized := false
				if requested != "" {
					for _, opt := range ext.Manifest.QualityOptions {
						if strings.EqualFold(strings.TrimSpace(opt.ID), requested) {
							recognized = true
							break
						}
					}
				}
				if !recognized {
					if best := strings.TrimSpace(ext.Manifest.QualityOptions[0].ID); best != "" {
						fallbackQuality = best
					}
				}
			}

			resp, cancelledOuter := attemptExtensionDownload(req, ext, provider, availability.TrackID, fallbackQuality, providerID, false, &lastErr, &lastErrType, &lastRetryAfterSeconds)
			if cancelledOuter {
				return nil, ErrDownloadCancelled
			}
			if resp != nil {
				return resp, nil
			}
			GoLog("[DownloadWithExtensionFallback] %s failed: %v\n", providerID, lastErr)

			if lastErr != nil {
				effType := lastErrType
				if effType == "" {
					effType = classifyDownloadErrorType(lastErr.Error())
				}
				if isOutputStorageWriteFailure(effType, lastErr.Error()) {
					GoLog("[DownloadWithExtensionFallback] %s hit an unwritable output path; stopping provider fallback\n", providerID)
					return buildOutputStorageFailureResponse(
						providerID,
						lastErr,
						lastRetryAfterSeconds,
					), nil
				}
				if strings.EqualFold(effType, "verification_required") {
					GoLog("[DownloadWithExtensionFallback] %s requires verification; pausing fallback to open the challenge\n", providerID)
					cachePreparedDownloadRequest(preparationKey, req)
					return &DownloadResponse{
						Success:           false,
						Error:             "Download failed: " + lastErr.Error(),
						ErrorType:         "verification_required",
						RetryAfterSeconds: lastRetryAfterSeconds,
						Service:           providerID,
					}, nil
				}
			}

			if terminalAvailability {
				GoLog("[DownloadWithExtensionFallback] %s requested skip_fallback after download failure\n", providerID)
				return buildExtensionFallbackStoppedResponse(providerID, availability, lastErr), nil
			}
		}
	}

	if lastErr != nil {
		errorType := firstNonEmptyTrimmed(lastErrType, classifyDownloadErrorType(lastErr.Error()))
		if errorType == "unknown" {
			errorType = "not_found"
		}
		return &DownloadResponse{
			Success:           false,
			Error:             "All providers failed. Last error: " + lastErr.Error(),
			ErrorType:         errorType,
			RetryAfterSeconds: lastRetryAfterSeconds,
		}, nil
	}

	return &DownloadResponse{
		Success:   false,
		Error:     "No extension download providers available",
		ErrorType: "not_found",
	}, nil
}
