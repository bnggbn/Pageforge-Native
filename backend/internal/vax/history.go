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
	sdk "github.com/bnggbn/vax-action-history/go/pkg/vax"
	"github.com/bnggbn/vax-action-history/go/pkg/vax/sae"
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
		return "", fmt.Errorf("invalid VAX salt")
	}
	genesis, err := sdk.ComputeGenesisSAI(actor, bytes)
	return hex.EncodeToString(genesis), err
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
		return "", fmt.Errorf("invalid VAX prevSAI")
	}
	sai, err := sdk.ComputeSAI(prev, []byte(envelope))
	return hex.EncodeToString(sai), err
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
	r.Envelope, err = Canonical(sae.Envelope{ActionType: "pageforge." + kind, Timestamp: timestamp.UnixMilli(),
		SDTO: map[string]any{"documentId": doc.ID, "revisionId": r.ID, "parentId": r.ParentID,
			"originalHash": doc.OriginalHash, "contentHash": Hash([]byte(content)), "notesHash": Hash([]byte(noteJSON)),
			"viewHash": view, "restoredFrom": restoredFrom}})
	if err != nil {
		return r, err
	}
	r.SAI, err = SAI(r.PrevSAI, r.Envelope)
	return r, err
}

// Verifier enforces Pageforge document identity, snapshots and event relationships.
// The official SDK supplies canonical bytes, genesis and SAI computation.
// It retains chain metadata, never historical snapshot strings or note arrays.
type Verifier struct {
	doc            model.Document
	view, previous string
	parent         *string
	ids            map[string]bool
	index          int
}

func NewVerifier(doc model.Document, originalHash string) (*Verifier, error) {
	genesis, err := Genesis(doc.Actor, doc.Salt)
	if err != nil || genesis != doc.Genesis || originalHash != doc.OriginalHash {
		return nil, fmt.Errorf("original file or revision source verification failed")
	}
	view, err := viewHash(doc)
	if err != nil {
		return nil, err
	}
	return &Verifier{doc: doc, view: view, previous: doc.Genesis, ids: map[string]bool{}}, nil
}

// AppendHashes consumes digests computed from verified snapshot bytes, not root IDs.
func (v *Verifier) AppendHashes(r model.Revision, contentHash, notesHash string) error {
	doc := v.doc

	allowed := r.Kind == "edit" || r.Kind == "note" || r.Kind == "restore" || r.Kind == "adopt"
	if (v.index == 0 && r.Kind != "import") || (v.index > 0 && !allowed) || r.BranchID != "" || v.ids[r.ID] ||
		r.PrevSAI != v.previous || !equalID(r.ParentID, v.parent) {
		return fmt.Errorf("document revision chain is discontinuous")
	}
	decoder := json.NewDecoder(strings.NewReader(r.Envelope))
	decoder.UseNumber()
	var env map[string]any
	if err := decoder.Decode(&env); err != nil {
		return err
	}
	canonical, err := Canonical(env)
	if err != nil || canonical != r.Envelope || env["action_type"] != "pageforge."+r.Kind {
		return fmt.Errorf("invalid VAX event")
	}
	data, ok := env["sdto"].(map[string]any)
	if !ok {
		return fmt.Errorf("invalid VAX payload")
	}
	stamp, ok := env["timestamp"].(json.Number)
	if !ok {
		return fmt.Errorf("invalid VAX timestamp")
	}
	ms, err := stamp.Int64()
	if err != nil || time.UnixMilli(ms).UTC().Format("2006-01-02T15:04:05.000Z") != r.CreatedAt {
		return fmt.Errorf("VAX timestamp does not match the revision")
	}
	expected := map[string]any{"documentId": doc.ID, "revisionId": r.ID, "parentId": r.ParentID,
		"originalHash": doc.OriginalHash, "contentHash": contentHash, "notesHash": notesHash, "viewHash": v.view}
	for key, value := range expected {
		a, _ := Canonical(data[key])
		b, _ := Canonical(value)
		if a != b {
			return fmt.Errorf("VAX snapshot field %s failed verification", key)
		}
	}
	if data["branchId"] != nil {
		return fmt.Errorf("document history cannot contain sandbox nodes")
	}
	a, _ := Canonical(data["adoptedFrom"])
	b, _ := Canonical(r.AdoptedFrom)
	if a != b || (r.Kind == "adopt") != (r.AdoptedFrom != nil) {
		return fmt.Errorf("invalid adoption source")
	}
	if r.Kind == "restore" {
		id, ok := data["restoredFrom"].(string)
		if !ok || !v.ids[id] {
			return fmt.Errorf("invalid restore source")
		}
	}
	computed, err := SAI(v.previous, r.Envelope)
	if err != nil || computed != r.SAI {
		return fmt.Errorf("VAX SAI verification failed")
	}
	v.ids[r.ID] = true
	v.previous = computed
	v.parent = &r.ID
	v.index++
	return nil
}

func Verify(doc model.Document, source []byte, revisions []model.Revision) error {
	verifier, err := NewVerifier(doc, Hash(source))
	if err != nil {
		return err
	}
	if len(revisions) == 0 {
		return fmt.Errorf("original file or revision source verification failed")
	}
	contentHashes := map[string]string{}
	for _, r := range revisions {
		notes, err := Canonical(r.Notes)
		if err != nil {
			return err
		}
		contentHash, found := contentHashes[r.Content]
		if !found {
			contentHash = Hash([]byte(r.Content))
			contentHashes[r.Content] = contentHash
		}
		if err = verifier.AppendHashes(r, contentHash, Hash([]byte(notes))); err != nil {
			return err
		}
	}
	return nil
}
func equalID(a, b *string) bool { return (a == nil && b == nil) || (a != nil && b != nil && *a == *b) }
