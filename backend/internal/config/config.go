package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Config struct {
	Transport struct {
		RequestTimeoutMs int `json:"requestTimeoutMs"`
		ResponseMiB      int `json:"responseMiB"`
	} `json:"transport"`
	Storage struct {
		InlineObjectBytes int    `json:"inlineObjectBytes"`
		ObjectCatalogMiB  int    `json:"objectCatalogMiB"`
		RevisionFormat    string `json:"revisionFormat"`
		ObjectCount       int    `json:"objectCount"`
		RecordMiB         int    `json:"recordMiB"`
		HistoryMiB        int    `json:"historyMiB"`
		VerifiedCacheMiB  int    `json:"verifiedCacheMiB"`
	} `json:"storage"`
	EvidenceWall struct {
		MaxTopics           int `json:"maxTopics"`
		TopicNameCharacters int `json:"topicNameCharacters"`
		LayoutMiB           int `json:"layoutMiB"`
		MaxCards            int `json:"maxCards"`
		MaxEdges            int `json:"maxEdges"`
		CanvasWidth         int `json:"canvasWidth"`
		CanvasHeight        int `json:"canvasHeight"`
		SaveDebounceMs      int `json:"saveDebounceMs"`
	} `json:"evidenceWall"`
	Paths struct {
		LibraryRoot string `json:"libraryRoot"`
	} `json:"paths"`
	Limits struct {
		TextMiB            int `json:"textMiB"`
		DocumentMiB        int `json:"documentMiB"`
		RequestMiB         int `json:"requestMiB"`
		RevisionCount      int `json:"revisionCount"`
		WorkingCopyCount   int `json:"workingCopyCount"`
		SnapshotNotesMiB   int `json:"snapshotNotesMiB"`
		NoteCharacters     int `json:"noteCharacters"`
		QuoteCharacters    int `json:"quoteCharacters"`
		LocationCharacters int `json:"locationCharacters"`
	} `json:"limits"`
	Reading struct {
		EditorSectionUnits int   `json:"editorSectionUnits"`
		DefaultFontSize    int   `json:"defaultFontSize"`
		FontSizes          []int `json:"fontSizes"`
		ProgressDebounceMs int   `json:"progressDebounceMs"`
		DraftDebounceMs    int   `json:"draftDebounceMs"`
	} `json:"reading"`
	Diff struct {
		MaxCharacters int `json:"maxCharacters"`
		TimeoutMs     int `json:"timeoutMs"`
	} `json:"diff"`
}

func Load(root string) (Config, error) {
	var c Config
	c.Reading.EditorSectionUnits = 16000
	c.Transport.RequestTimeoutMs = 30000
	c.Transport.ResponseMiB = 64
	c.Storage.InlineObjectBytes = 65536
	c.Storage.ObjectCatalogMiB = 8
	c.Storage.RevisionFormat = "objects-v1"
	c.Storage.ObjectCount = 100000
	c.Storage.RecordMiB = 64
	c.Storage.HistoryMiB = 256
	c.Storage.VerifiedCacheMiB = 64
	c.EvidenceWall.MaxTopics = 32
	c.EvidenceWall.TopicNameCharacters = 80
	c.EvidenceWall.LayoutMiB = 4
	c.EvidenceWall.MaxCards = 500
	c.EvidenceWall.MaxEdges = 1000
	c.EvidenceWall.CanvasWidth = 6400
	c.EvidenceWall.CanvasHeight = 6400
	c.EvidenceWall.SaveDebounceMs = 500
	defaults, err := os.ReadFile(filepath.Join(root, "pageforge.config.json"))
	if err != nil {
		return c, err
	}
	var merged map[string]any
	if err = json.Unmarshal(defaults, &merged); err != nil {
		return c, err
	}
	local, err := os.ReadFile(filepath.Join(root, "pageforge.config.local.json"))
	if err == nil {
		var override map[string]any
		if err = json.Unmarshal(local, &override); err != nil {
			return c, err
		}
		merge(merged, override)
	} else if !os.IsNotExist(err) {
		return c, err
	}
	encoded, _ := json.Marshal(merged)
	if err = json.Unmarshal(encoded, &c); err != nil {
		return c, err
	}
	if env := os.Getenv("PAGEFORGE_LIBRARY_ROOT"); env != "" {
		c.Paths.LibraryRoot = env
	}
	if c.EvidenceWall.MaxTopics < 1 ||
		c.EvidenceWall.MaxTopics > 100 ||
		c.EvidenceWall.TopicNameCharacters < 4 ||
		c.EvidenceWall.TopicNameCharacters > 200 ||
		c.EvidenceWall.LayoutMiB < 1 ||
		c.EvidenceWall.LayoutMiB > 16 ||
		c.EvidenceWall.MaxCards < 1 ||
		c.EvidenceWall.MaxCards > 2000 ||
		c.EvidenceWall.MaxEdges < 1 ||
		c.EvidenceWall.MaxEdges > 4000 ||
		c.EvidenceWall.CanvasWidth < 1000 ||
		c.EvidenceWall.CanvasWidth > 20000 ||
		c.EvidenceWall.CanvasHeight < 1000 ||
		c.EvidenceWall.CanvasHeight > 20000 ||
		c.EvidenceWall.SaveDebounceMs < 100 {
		return c, fmt.Errorf("invalid evidence wall configuration")
	}
	if c.Reading.EditorSectionUnits < 1000 || c.Reading.EditorSectionUnits > 65536 {
		return c, fmt.Errorf("invalid editor section configuration")
	}
	if c.Transport.RequestTimeoutMs < 1000 || c.Transport.RequestTimeoutMs > 120000 ||
		c.Transport.ResponseMiB < 1 || c.Transport.ResponseMiB > 512 {
		return c, fmt.Errorf("invalid HTTP read configuration")
	}
	if (c.Storage.RevisionFormat != "legacy" && c.Storage.RevisionFormat != "objects-v1") ||
		c.Storage.ObjectCount < 1 || c.Storage.ObjectCount > 1000000 ||
		c.Storage.InlineObjectBytes < 0 || c.Storage.InlineObjectBytes > 65536 ||
		c.Storage.ObjectCatalogMiB < 1 || c.Storage.ObjectCatalogMiB > 32 {
		return c, fmt.Errorf("invalid content object configuration")
	}
	if c.Storage.RecordMiB < 1 || c.Storage.RecordMiB > 512 ||
		c.Storage.HistoryMiB < c.Storage.RecordMiB || c.Storage.HistoryMiB > 4096 ||
		c.Storage.VerifiedCacheMiB < 0 || c.Storage.VerifiedCacheMiB > 512 {
		return c, fmt.Errorf("invalid history read or cache configuration")
	}
	if c.Paths.LibraryRoot == "" || c.Limits.TextMiB < 1 || c.Limits.RequestMiB < c.Limits.TextMiB*2 ||
		c.Limits.RevisionCount < 1 || c.Limits.WorkingCopyCount < 1 || c.Diff.MaxCharacters < 1 ||
		c.Diff.TimeoutMs < 1 || c.Reading.DefaultFontSize < 1 || c.Reading.DraftDebounceMs < 1 {
		return c, fmt.Errorf("invalid capacity, reading or diff limits")
	}
	if !filepath.IsAbs(c.Paths.LibraryRoot) {
		c.Paths.LibraryRoot = filepath.Join(root, c.Paths.LibraryRoot)
	}
	c.Paths.LibraryRoot, err = filepath.Abs(c.Paths.LibraryRoot)
	return c, err
}

func merge(base, override map[string]any) {
	for k, v := range override {
		if child, ok := v.(map[string]any); ok {
			target, ok := base[k].(map[string]any)
			if !ok {
				target = map[string]any{}
				base[k] = target
			}
			merge(target, child)
		} else {
			base[k] = v
		}
	}
}
