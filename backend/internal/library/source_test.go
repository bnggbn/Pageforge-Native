package library

import "testing"

func TestUTF8BOMMatchesWebImport(t *testing.T) {
	store := testStore(t)
	id, _, err := store.Import("BOM.md", append([]byte{0xef, 0xbb, 0xbf}, []byte("# Heading\n")...))
	if err != nil {
		t.Fatal(err)
	}
	book, err := store.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	if book.Revisions[0].Content != "# Heading\n" {
		t.Fatal("BOM leaked into the working text")
	}
	if _, _, err = store.Import("empty.txt", []byte{0xef, 0xbb, 0xbf}); err == nil {
		t.Fatal("empty BOM imported")
	}
}
