package compare

import (
	"fmt"
	"time"
	"unicode/utf16"

	"github.com/sergi/go-diff/diffmatchpatch"
)

type Part struct {
	Kind string `json:"kind"`
	Text string `json:"text"`
}

func Text(before, after string, maxCharacters, timeoutMs int) ([]Part, error) {
	if len(utf16.Encode([]rune(before)))+len(utf16.Encode([]rune(after))) > maxCharacters {
		return nil, fmt.Errorf("comparison exceeds the configured limit; export the content to compare it")
	}
	dmp := diffmatchpatch.New()
	dmp.DiffTimeout = time.Duration(timeoutMs) * time.Millisecond
	diffs := dmp.DiffMain(before, after, true)
	result := make([]Part, 0, len(diffs))
	for _, diff := range diffs {
		kind := "equal"
		if diff.Type == diffmatchpatch.DiffInsert {
			kind = "insert"
		} else if diff.Type == diffmatchpatch.DiffDelete {
			kind = "delete"
		}
		result = append(result, Part{Kind: kind, Text: diff.Text})
	}
	return result, nil
}
