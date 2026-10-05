package design

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
)

const MaxBytes = 16384

type Theme struct {
	Paper       string `json:"paper"`
	Ink         string `json:"ink"`
	Accent      string `json:"accent"`
	Forest      string `json:"forest"`
	Muted       string `json:"muted"`
	HeadingFont string `json:"headingFont"`
}
type Library struct {
	ShowInvitation bool    `json:"showInvitation"`
	CardWidth      float64 `json:"cardWidth"`
	Gap            float64 `json:"gap"`
	CoverArt       string  `json:"coverArt"`
}
type Reader struct {
	ParagraphGapLines float64 `json:"paragraphGapLines"`
	PageWidth         float64 `json:"pageWidth"`
	LineHeight        float64 `json:"lineHeight"`
}
type Document struct {
	SchemaVersion int     `json:"schemaVersion"`
	Theme         Theme   `json:"theme"`
	Library       Library `json:"library"`
	Reader        Reader  `json:"reader"`
}
type Snapshot struct {
	Document Document `json:"document"`
	Revision string   `json:"revision"`
}

var colorPattern = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)

func Decode(data []byte) (Document, error) {
	var document Document
	document.Reader.ParagraphGapLines = 1
	if len(data) > MaxBytes {
		return document, fmt.Errorf("外觀 JSON 超過 16 KiB")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&document); err != nil {
		return document, err
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return document, fmt.Errorf("外觀 JSON 有多餘資料")
	}
	// Reject omitted fields, including false/zero values that Go would otherwise default.
	var shape map[string]json.RawMessage
	json.Unmarshal(data, &shape)
	for name, fields := range map[string][]string{
		"theme":   {"paper", "ink", "accent", "forest", "muted", "headingFont"},
		"library": {"showInvitation", "cardWidth", "gap", "coverArt"},
		"reader":  {"pageWidth", "lineHeight"},
	} {
		var members map[string]json.RawMessage
		json.Unmarshal(shape[name], &members)
		for _, field := range fields {
			if len(members[field]) == 0 || bytes.Equal(members[field], []byte("null")) {
				return document, fmt.Errorf("缺少 %s.%s", name, field)
			}
		}
	}
	var readerShape map[string]json.RawMessage
	json.Unmarshal(shape["reader"], &readerShape)
	if bytes.Equal(readerShape["paragraphGapLines"], []byte("null")) {
		return document, fmt.Errorf("reader.paragraphGapLines 不可為 null")
	}
	return document, document.Validate()
}
func (d Document) Validate() error {
	if d.SchemaVersion != 1 {
		return fmt.Errorf("不支援的 schemaVersion")
	}
	for name, value := range map[string]string{"paper": d.Theme.Paper, "ink": d.Theme.Ink, "accent": d.Theme.Accent, "forest": d.Theme.Forest, "muted": d.Theme.Muted} {
		if !colorPattern.MatchString(value) {
			return fmt.Errorf("theme.%s 必須為 #RRGGBB", name)
		}
	}
	switch d.Theme.HeadingFont {
	case "Georgia", "Noto Serif TC", "Microsoft JhengHei":
	default:
		return fmt.Errorf("不支援的 headingFont")
	}
	switch d.Library.CoverArt {
	case "auto", "rings", "frames", "waves", "leaf", "arch":
	default:
		return fmt.Errorf("不支援的 coverArt")
	}
	if !(d.Library.CardWidth >= 220 && d.Library.CardWidth <= 340) {
		return fmt.Errorf("library.cardWidth 必須在 220–340")
	}
	if !(d.Library.Gap >= 12 && d.Library.Gap <= 48) {
		return fmt.Errorf("library.gap 必須在 12–48")
	}
	if !(d.Reader.PageWidth >= 480 && d.Reader.PageWidth <= 1000) {
		return fmt.Errorf("reader.pageWidth 必須在 480–1000")
	}
	if !(d.Reader.LineHeight >= 1.3 && d.Reader.LineHeight <= 2.4) {
		return fmt.Errorf("reader.lineHeight 必須在 1.3–2.4")
	}
	if !(d.Reader.ParagraphGapLines >= 0 && d.Reader.ParagraphGapLines <= 3) {
		return fmt.Errorf("reader.paragraphGapLines 必須在 0–3")
	}
	return nil
}
func snapshot(d Document) Snapshot {
	data, _ := json.Marshal(d)
	hash := sha256.Sum256(data)
	return Snapshot{d, hex.EncodeToString(hash[:])}
}
