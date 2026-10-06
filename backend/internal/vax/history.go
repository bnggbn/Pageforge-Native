package vax

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

func UUID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
}
func Now() string             { return time.Now().UTC().Format("2006-01-02T15:04:05.000Z") }
func Hash(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }
func Genesis(actor, salt string) (string, error) {
	bytes, err := hex.DecodeString(salt)
	if err != nil || len(bytes) != 16 {
		return "", fmt.Errorf("VAX salt 無效")
	}
	return Hash(append(append([]byte("VAX-GENESIS"), []byte(actor)...), bytes...)), nil
}
func NewGenesis(actor string) (string, string) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		panic(err)
	}
	encoded := hex.EncodeToString(salt)
	genesis, _ := Genesis(actor, encoded)
	return encoded, genesis
}
func SAI(previous, envelope string) (string, error) {
	prev, err := hex.DecodeString(previous)
	if err != nil || len(prev) != 32 {
		return "", fmt.Errorf("VAX prevSAI 無效")
	}
	hashed := sha256.Sum256([]byte(envelope))
	return Hash(append(append([]byte("VAX-SAI"), prev...), hashed[:]...)), nil
}
func viewHash(doc model.Document) (string, error) {
	value, err := Canonical(map[string]any{"title": doc.Title, "filename": doc.Filename,
		"format": doc.Format, "sections": doc.Sections, "sheets": doc.Sheets})
	return Hash([]byte(value)), err
}
func Create(doc model.Document, parent *model.Revision, kind, content string, notes []model.Note, restoredFrom *string) (model.Revision, error) {
	if notes == nil {
		notes = []model.Note{}
	}
	r := model.Revision{ID: UUID(), Kind: kind, CreatedAt: Now(), Content: content, Notes: notes, PrevSAI: doc.Genesis}
	if parent != nil {
		r.ParentID = &parent.ID
		r.PrevSAI = parent.SAI
	}
	view, err := viewHash(doc)
	if err != nil {
		return r, err
	}
	noteJSON, err := Canonical(notes)
	if err != nil {
		return r, err
	}
	timestamp, _ := time.Parse(time.RFC3339Nano, r.CreatedAt)
	r.Envelope, err = Canonical(map[string]any{"action_type": "pageforge." + kind, "timestamp": timestamp.UnixMilli(),
		"sdto": map[string]any{"documentId": doc.ID, "revisionId": r.ID, "parentId": r.ParentID,
			"originalHash": doc.OriginalHash, "contentHash": Hash([]byte(content)), "notesHash": Hash([]byte(noteJSON)),
			"viewHash": view, "restoredFrom": restoredFrom}})
	if err != nil {
		return r, err
	}
	r.SAI, err = SAI(r.PrevSAI, r.Envelope)
	return r, err
}
func Verify(doc model.Document, source []byte, revisions []model.Revision) error {
	genesis, err := Genesis(doc.Actor, doc.Salt)
	if err != nil || genesis != doc.Genesis || Hash(source) != doc.OriginalHash || len(revisions) == 0 {
		return fmt.Errorf("原始檔或版本來源驗證失敗")
	}
	view, err := viewHash(doc)
	if err != nil {
		return err
	}
	previous := doc.Genesis
	var parent *string
	ids := map[string]bool{}
	// Exact immutable text values may be shared by many note-only revisions.
	contentHashes := map[string]string{}
	for index, r := range revisions {
		allowed := r.Kind == "edit" || r.Kind == "note" || r.Kind == "restore" || r.Kind == "adopt"
		if (index == 0 && r.Kind != "import") || (index > 0 && !allowed) || r.BranchID != "" || ids[r.ID] ||
			r.PrevSAI != previous || !equalID(r.ParentID, parent) {
			return fmt.Errorf("主線版本鏈不連續")
		}
		decoder := json.NewDecoder(strings.NewReader(r.Envelope))
		decoder.UseNumber()
		var env map[string]any
		if err := decoder.Decode(&env); err != nil {
			return err
		}
		canonical, err := Canonical(env)
		if err != nil || canonical != r.Envelope || env["action_type"] != "pageforge."+r.Kind {
			return fmt.Errorf("VAX 事件無效")
		}
		data, ok := env["sdto"].(map[string]any)
		if !ok {
			return fmt.Errorf("VAX payload 無效")
		}
		stamp, ok := env["timestamp"].(json.Number)
		if !ok {
			return fmt.Errorf("VAX 時間無效")
		}
		ms, err := stamp.Int64()
		if err != nil || time.UnixMilli(ms).UTC().Format("2006-01-02T15:04:05.000Z") != r.CreatedAt {
			return fmt.Errorf("VAX 時間不一致")
		}
		notes, err := Canonical(r.Notes)
		if err != nil {
			return err
		}
		contentHash, found := contentHashes[r.Content]
		if !found {
			contentHash = Hash([]byte(r.Content))
			contentHashes[r.Content] = contentHash
		}
		expected := map[string]any{"documentId": doc.ID, "revisionId": r.ID, "parentId": r.ParentID,
			"originalHash": doc.OriginalHash, "contentHash": contentHash, "notesHash": Hash([]byte(notes)), "viewHash": view}
		for key, value := range expected {
			a, _ := Canonical(data[key])
			b, _ := Canonical(value)
			if a != b {
				return fmt.Errorf("VAX 快照 %s 驗證失敗", key)
			}
		}
		if data["branchId"] != nil {
			return fmt.Errorf("主線不可包含沙盒節點")
		}
		a, _ := Canonical(data["adoptedFrom"])
		b, _ := Canonical(r.AdoptedFrom)
		if a != b || (r.Kind == "adopt") != (r.AdoptedFrom != nil) {
			return fmt.Errorf("採納來源無效")
		}
		if r.Kind == "restore" {
			id, ok := data["restoredFrom"].(string)
			if !ok || !ids[id] {
				return fmt.Errorf("還原來源無效")
			}
		}
		computed, err := SAI(previous, r.Envelope)
		if err != nil || computed != r.SAI {
			return fmt.Errorf("VAX SAI 驗證失敗")
		}
		ids[r.ID] = true
		previous = computed
		parent = &revisions[index].ID
	}
	return nil
}
func equalID(a, b *string) bool { return (a == nil && b == nil) || (a != nil && b != nil && *a == *b) }
