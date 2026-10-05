package vax

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

func TestWebSDKCompatibility(t *testing.T) {
	bytes, err := os.ReadFile("testdata/web-history.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Document  model.Document   `json:"document"`
		Source    string           `json:"source"`
		Revisions []model.Revision `json:"revisions"`
	}
	if err = json.Unmarshal(bytes, &fixture); err != nil {
		t.Fatal(err)
	}
	if err = Verify(fixture.Document, []byte(fixture.Source), fixture.Revisions); err != nil {
		t.Fatal(err)
	}
	parent := fixture.Revisions[len(fixture.Revisions)-1]
	revision, err := Create(fixture.Document, &parent, "edit", fixture.Source+"來自 Go 的版本 ✨", parent.Notes, nil)
	if err != nil {
		t.Fatal(err)
	}
	fixture.Revisions = append(fixture.Revisions, revision)
	if err = Verify(fixture.Document, []byte(fixture.Source), fixture.Revisions); err != nil {
		t.Fatal(err)
	}
	if target := os.Getenv("PAGEFORGE_COMPAT_EXPORT"); target != "" {
		encoded, _ := json.MarshalIndent(fixture, "", "  ")
		if err = os.WriteFile(target, encoded, 0600); err != nil {
			t.Fatal(err)
		}
	}
	fixture.Revisions[1].Content += "篡改"
	if Verify(fixture.Document, []byte(fixture.Source), fixture.Revisions) == nil {
		t.Fatal("accepted changed snapshot")
	}
}

func TestCanonicalUnicodeAndSorting(t *testing.T) {
	got, err := Canonical(map[string]any{"🌿": "中文\n\t\"", "a": 1720000000000})
	if err != nil {
		t.Fatal(err)
	}
	want := `{"a":1720000000000,"\ud83c\udf3f":"\u4e2d\u6587\n\t\""}`
	if got != want {
		t.Fatalf("canonical bytes mismatch\ngot %s\nwant %s", got, want)
	}
	if _, err = Canonical(map[string]any{"number": 0.1}); err == nil {
		t.Fatal("unsupported wire number accepted")
	}
}
