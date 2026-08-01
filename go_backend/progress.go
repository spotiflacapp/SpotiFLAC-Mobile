package gobackend

import (
	"encoding/json"
	"math"
	"sort"
	"sync"
	"time"
)

type DownloadProgress struct {
	CurrentFile   string  `json:"current_file"`
	Progress      float64 `json:"progress"`
	Speed         float64 `json:"speed_mbps"`
	BytesTotal    int64   `json:"bytes_total"`
	BytesReceived int64   `json:"bytes_received"`
	IsDownloading bool    `json:"is_downloading"`
	Status        string  `json:"status"`
	Stage         string  `json:"stage,omitempty"`
}

type ItemProgress struct {
	ItemID        string  `json:"item_id"`
	BytesTotal    int64   `json:"bytes_total"`
	BytesReceived int64   `json:"bytes_received"`
	Progress      float64 `json:"progress"`
	SpeedMBps     float64 `json:"speed_mbps"`
	IsDownloading bool    `json:"is_downloading"`
	Status        string  `json:"status"`
	Stage         string  `json:"stage,omitempty"`
	revision      int64
}

const (
	itemProgressStatusPreparing   = "preparing"
	itemProgressStatusDownloading = "downloading"
	itemProgressStatusCompleted   = "completed"
	itemProgressStatusFinalizing  = "finalizing"
)

type MultiProgress struct {
	Items map[string]*ItemProgress `json:"items"`
}

type MultiProgressDelta struct {
	Seq     int64                    `json:"seq"`
	Reset   bool                     `json:"reset,omitempty"`
	Items   map[string]*ItemProgress `json:"items,omitempty"`
	Removed []string                 `json:"removed,omitempty"`
}

type progressBridgeState struct {
	bytesBucket   int64
	bytesTotal    int64
	progressPct   int64
	speedDeciMBps int64
	downloading   bool
	status        string
	stage         string
}

var (
	multiProgress       = MultiProgress{Items: make(map[string]*ItemProgress)}
	multiMu             sync.RWMutex
	multiProgressDirty  = true
	cachedMultiProgress = "{\"items\":{}}"
	multiProgressSeq    int64
	multiProgressReset  int64
	removedProgressSeq  = make(map[string]int64)
)

func markMultiProgressDirtyLocked() {
	multiProgressDirty = true
}

func nextMultiProgressSeqLocked() int64 {
	multiProgressSeq++
	return multiProgressSeq
}

func itemProgressBridgeState(item *ItemProgress) progressBridgeState {
	progress := item.Progress
	if math.IsNaN(progress) || progress <= 0 {
		progress = 0
	} else if progress >= 1 {
		progress = 1
	}

	speed := item.SpeedMBps
	if math.IsNaN(speed) || speed <= 0 {
		speed = 0
	}

	return progressBridgeState{
		bytesBucket:   item.BytesReceived / progressUpdateThreshold,
		bytesTotal:    item.BytesTotal,
		progressPct:   int64(math.Round(progress * 100)),
		speedDeciMBps: int64(math.Round(speed * 10)),
		downloading:   item.IsDownloading,
		status:        item.Status,
		stage:         item.Stage,
	}
}

func markMultiProgressDirtyIfChangedLocked(item *ItemProgress, before progressBridgeState) {
	if itemProgressBridgeState(item) != before {
		item.revision = nextMultiProgressSeqLocked()
		markMultiProgressDirtyLocked()
	}
}

func GetMultiProgress() string {
	multiMu.RLock()
	if !multiProgressDirty {
		cached := cachedMultiProgress
		multiMu.RUnlock()
		return cached
	}
	multiMu.RUnlock()

	multiMu.Lock()
	defer multiMu.Unlock()
	if !multiProgressDirty {
		return cachedMultiProgress
	}
	jsonBytes, err := json.Marshal(multiProgress)
	if err != nil {
		return "{\"items\":{}}"
	}
	cachedMultiProgress = string(jsonBytes)
	multiProgressDirty = false
	return cachedMultiProgress
}

func GetMultiProgressDelta(sinceSeq int64) string {
	multiMu.RLock()
	currentSeq := multiProgressSeq
	if sinceSeq >= currentSeq {
		multiMu.RUnlock()
		return ""
	}

	reset := sinceSeq <= 0 || sinceSeq < multiProgressReset
	delta := MultiProgressDelta{
		Seq:   currentSeq,
		Reset: reset,
	}
	if reset {
		if len(multiProgress.Items) > 0 {
			delta.Items = make(map[string]*ItemProgress, len(multiProgress.Items))
			for id, item := range multiProgress.Items {
				copy := *item
				copy.revision = 0
				delta.Items[id] = &copy
			}
		}
	} else {
		for id, item := range multiProgress.Items {
			if item.revision > sinceSeq {
				if delta.Items == nil {
					delta.Items = make(map[string]*ItemProgress)
				}
				copy := *item
				copy.revision = 0
				delta.Items[id] = &copy
			}
		}
		for id, revision := range removedProgressSeq {
			if revision > sinceSeq {
				delta.Removed = append(delta.Removed, id)
			}
		}
	}
	multiMu.RUnlock()

	jsonBytes, err := json.Marshal(delta)
	if err != nil {
		return ""
	}
	return string(jsonBytes)
}

func StartItemProgress(itemID string) {
	multiMu.Lock()
	defer multiMu.Unlock()

	multiProgress.Items[itemID] = &ItemProgress{
		ItemID:        itemID,
		BytesTotal:    0,
		BytesReceived: 0,
		Progress:      0,
		IsDownloading: false,
		Status:        itemProgressStatusPreparing,
		revision:      nextMultiProgressSeqLocked(),
	}
	delete(removedProgressSeq, itemID)
	markMultiProgressDirtyLocked()
}

func SetItemPreparing(itemID string) {
	SetItemPreparingStage(itemID, "")
}

func SetItemPreparingStage(itemID, stage string) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.Progress = 0
		item.BytesReceived = 0
		item.BytesTotal = 0
		item.SpeedMBps = 0
		item.IsDownloading = true
		item.Status = itemProgressStatusPreparing
		item.Stage = stage
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func SetItemDownloading(itemID string) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.IsDownloading = true
		item.Status = itemProgressStatusDownloading
		item.Stage = ""
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func SetItemBytesTotal(itemID string, total int64) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.BytesTotal = total
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func SetItemBytesReceived(itemID string, received int64) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.BytesReceived = received
		if item.BytesTotal > 0 {
			item.Progress = float64(received) / float64(item.BytesTotal)
		}
		if received > 0 {
			item.IsDownloading = true
			item.Status = itemProgressStatusDownloading
			item.Stage = ""
		}
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func SetItemBytesReceivedWithSpeed(itemID string, received int64, speedMBps float64) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.BytesReceived = received
		item.SpeedMBps = speedMBps
		if item.BytesTotal > 0 {
			item.Progress = float64(received) / float64(item.BytesTotal)
		}
		if received > 0 {
			item.IsDownloading = true
			item.Status = itemProgressStatusDownloading
			item.Stage = ""
		}
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func CompleteItemProgress(itemID string) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.Progress = 1.0
		item.IsDownloading = false
		item.Status = itemProgressStatusCompleted
		item.Stage = ""
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func SetItemProgress(itemID string, progress float64, bytesReceived, bytesTotal int64) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		hasByteProgress := bytesReceived > 0 || bytesTotal > 0
		if item.Status != itemProgressStatusPreparing || hasByteProgress || progress >= 1 {
			item.Progress = progress
		} else {
			item.Progress = 0
		}
		if bytesReceived > 0 {
			item.BytesReceived = bytesReceived
		}
		if bytesTotal > 0 {
			item.BytesTotal = bytesTotal
		}
		if hasByteProgress || progress >= 1 || item.Status == itemProgressStatusDownloading {
			item.IsDownloading = true
			item.Status = itemProgressStatusDownloading
			item.Stage = ""
		}
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

func SetItemFinalizing(itemID string) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		before := itemProgressBridgeState(item)
		item.Progress = 1.0
		item.Status = itemProgressStatusFinalizing
		item.Stage = ""
		markMultiProgressDirtyIfChangedLocked(item, before)
	}
}

// maxRemovedProgressEntries bounds the removal tombstones a long batch session
// can accumulate; pruning bumps multiProgressReset so lagging delta clients
// fall back to a full resync instead of missing removals.
const maxRemovedProgressEntries = 512

func RemoveItemProgress(itemID string) {
	multiMu.Lock()
	defer multiMu.Unlock()

	if _, ok := multiProgress.Items[itemID]; ok {
		delete(multiProgress.Items, itemID)
		removedProgressSeq[itemID] = nextMultiProgressSeqLocked()
		if len(removedProgressSeq) > maxRemovedProgressEntries {
			pruneRemovedProgressLocked()
		}
	}
	markMultiProgressDirtyLocked()
}

func pruneRemovedProgressLocked() {
	revisions := make([]int64, 0, len(removedProgressSeq))
	for _, revision := range removedProgressSeq {
		revisions = append(revisions, revision)
	}
	sort.Slice(revisions, func(i, j int) bool { return revisions[i] < revisions[j] })
	cutoff := revisions[len(revisions)/2]
	for id, revision := range removedProgressSeq {
		if revision <= cutoff {
			delete(removedProgressSeq, id)
		}
	}
	if cutoff > multiProgressReset {
		multiProgressReset = cutoff
	}
}

func GetItemProgress(itemID string) string {
	multiMu.RLock()
	defer multiMu.RUnlock()

	if item, ok := multiProgress.Items[itemID]; ok {
		jsonBytes, _ := json.Marshal(item)
		return string(jsonBytes)
	}
	return "{}"
}

func ClearAllItemProgress() {
	multiMu.Lock()
	defer multiMu.Unlock()

	multiProgress.Items = make(map[string]*ItemProgress)
	removedProgressSeq = make(map[string]int64)
	multiProgressReset = nextMultiProgressSeqLocked()
	markMultiProgressDirtyLocked()
}

func setDownloadDir(_ string) error {
	return nil
}

type ItemProgressWriter struct {
	writer       interface{ Write([]byte) (int, error) }
	itemID       string
	current      int64
	lastReported int64
	startTime    time.Time
	lastTime     time.Time
	lastBytes    int64
}

const progressUpdateThreshold = 128 * 1024

func NewItemProgressWriter(w interface{ Write([]byte) (int, error) }, itemID string) *ItemProgressWriter {
	now := time.Now()
	return &ItemProgressWriter{
		writer:       w,
		itemID:       itemID,
		current:      0,
		lastReported: 0,
		startTime:    now,
		lastTime:     now,
		lastBytes:    0,
	}
}

func (pw *ItemProgressWriter) Write(p []byte) (int, error) {
	if pw.itemID != "" && isDownloadCancelled(pw.itemID) {
		return 0, ErrDownloadCancelled
	}
	n, err := pw.writer.Write(p)
	if err != nil {
		return n, err
	}
	pw.current += int64(n)

	if pw.lastReported == 0 || pw.current-pw.lastReported >= progressUpdateThreshold {
		now := time.Now()
		elapsed := now.Sub(pw.lastTime).Seconds()
		var speedMBps float64
		if elapsed > 0 {
			bytesInInterval := pw.current - pw.lastBytes
			speedMBps = float64(bytesInInterval) / (1024 * 1024) / elapsed
		}

		SetItemBytesReceivedWithSpeed(pw.itemID, pw.current, speedMBps)
		pw.lastReported = pw.current
		pw.lastTime = now
		pw.lastBytes = pw.current
	}
	return n, nil
}
