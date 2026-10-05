package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Config struct {
	EvidenceWall struct {
		MaxCards       int `json:"maxCards"`
		MaxEdges       int `json:"maxEdges"`
		CanvasWidth    int `json:"canvasWidth"`
		CanvasHeight   int `json:"canvasHeight"`
		SaveDebounceMs int `json:"saveDebounceMs"`
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
	if c.EvidenceWall.MaxCards < 1 || c.EvidenceWall.MaxCards > 2000 || c.EvidenceWall.MaxEdges < 1 || c.EvidenceWall.MaxEdges > 4000 ||
		c.EvidenceWall.CanvasWidth < 1000 || c.EvidenceWall.CanvasWidth > 20000 || c.EvidenceWall.CanvasHeight < 1000 || c.EvidenceWall.CanvasHeight > 20000 || c.EvidenceWall.SaveDebounceMs < 100 {
		return c, fmt.Errorf("線索牆設定無效")
	}
	if c.Paths.LibraryRoot == "" || c.Limits.TextMiB < 1 || c.Limits.RequestMiB < c.Limits.TextMiB*2 ||
		c.Limits.RevisionCount < 1 || c.Limits.WorkingCopyCount < 1 || c.Diff.MaxCharacters < 1 ||
		c.Diff.TimeoutMs < 1 || c.Reading.DefaultFontSize < 1 || c.Reading.DraftDebounceMs < 1 {
		return c, fmt.Errorf("設定容量、閱讀或 diff 限制無效")
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
