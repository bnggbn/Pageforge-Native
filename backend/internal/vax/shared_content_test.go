package vax

import (
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"strings"
	"testing"
)

func TestSharedTextHashesStillRejectSameSizeCorruption(t *testing.T) {
	source := strings.Repeat("abc文字🌿\n", 4000)
	id := UUID()
	actor := "pageforge:" + id
	salt, genesis := NewGenesis(actor)
	doc := model.Document{ID: id, Actor: actor, Salt: salt, Genesis: genesis, OriginalHash: Hash([]byte(source)), Format: "text", Title: "shared"}
	first, err := Create(doc, nil, "import", source, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	versions := []model.Revision{first}
	for i := 1; i < 20; i++ {
		previous := versions[len(versions)-1]
		next, err := Create(doc, &previous, "note", source, []model.Note{{ID: UUID(), Body: "note"}}, nil)
		if err != nil {
			t.Fatal(err)
		}
		versions = append(versions, next)
	}
	if err = Verify(doc, []byte(source), versions); err != nil {
		t.Fatal(err)
	}
	versions[len(versions)-1].Content = "x" + source[1:]
	if err = Verify(doc, []byte(source), versions); err == nil {
		t.Fatal("same-size modified text bypassed verification")
	}
}
