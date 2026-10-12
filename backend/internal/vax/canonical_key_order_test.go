package vax

import "testing"

func TestOfficialCanonicalUnicodeKeyOrder(t *testing.T) {
	input := map[string]any{"！": 1, "😀": 2}
	canonical, err := Canonical(input)
	if err != nil {
		t.Fatal(err)
	}
	const expected = `{"\ud83d\ude00":2,"\uff01":1}`
	if canonical != expected {
		t.Fatalf("got %q; want %q", canonical, expected)
	}
}
