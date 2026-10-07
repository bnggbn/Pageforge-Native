package content

import (
	"math/rand"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestUnicodeBoundaryPolicyAndOldTreesRemainReadable(t *testing.T) {
	for _, alphabet := range []string{"abcdefghijklmnopqrstuvwxyz0123456789", "文件閱讀段落版本筆記線索創作保存歷史中文", "🌿😀🚀🧠🎨📖📎✨🧵💡🔍🔗"} {
		t.Run(alphabet, func(t *testing.T) {
			pool := []rune(alphabet)
			random := rand.New(rand.NewSource(526))
			var body strings.Builder
			for i := 0; i < 700000; i++ {
				body.WriteRune(pool[random.Intn(len(pool))])
			}
			source := body.String()
			store := fixtureStore(t)
			old, err := store.putText(source, 32767)
			if err != nil {
				t.Fatal(err)
			}
			current, err := store.PutText(source)
			if err != nil {
				t.Fatal(err)
			}
			session := store.Session(20*1024*1024, 10000)
			for _, ref := range []Ref{old, current} {
				text, err := session.Text(ref, 10*1024*1024)
				if err != nil || text != source {
					t.Fatal("boundary policy changed readable content", err)
				}
			}
			hard := func(root Ref) (int, int) {
				n, forced := 0, 0
				var walk func(Ref)
				walk = func(ref Ref) {
					node := session.objects[ref.Hash]
					if node.kind == textKind {
						n++
						// MaxChunk can be short by up to three bytes to retain a whole rune.
						if len(node.payload) >= MaxChunk-utf8.UTFMax+1 {
							forced++
						}
						return
					}
					for _, child := range node.children {
						walk(child)
					}
				}
				walk(root)
				return forced, n
			}
			oldHard, oldCount := hard(old)
			newHard, newCount := hard(current)
			t.Logf("hard-limit leaves old=%d/%d current=%d/%d", oldHard, oldCount, newHard, newCount)
			if oldHard == 0 || newHard*oldCount >= oldHard*newCount {
				t.Fatal("hard-limit ratio did not improve")
			}
			before := diskBytes(t, store.root)
			inserted, err := store.PutText("插入一句話🌿。\n" + source)
			if err != nil {
				t.Fatal(err)
			}
			if added := diskBytes(t, store.root) - before; added > int64(len(source))/4 {
				t.Fatalf("prefix insertion rewrote too much: %d", added)
			}
			text, err := store.Session(20*1024*1024, 10000).Text(inserted, 10*1024*1024)
			if err != nil || text != "插入一句話🌿。\n"+source {
				t.Fatal(err)
			}
		})
	}
}
