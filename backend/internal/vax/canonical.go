// Package vax adapts the official VAX Go SDK to Pageforge document events.
// Protocol encoding and chain hash primitives belong to the pinned upstream release.
package vax

import (
	"bytes"
	"encoding/json"
	"fmt"

	"github.com/bnggbn/vax-action-history/go/pkg/vax/jcs"
)

func Canonical(value any) (string, error) {
	raw, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var tree any
	if err = decoder.Decode(&tree); err != nil {
		return "", err
	}
	// Pageforge snapshots and timestamps use safe integers. This is an application
	// restriction; the SDK owns serialization, ordering and Unicode escaping.
	if err = validateNumbers(tree); err != nil {
		return "", err
	}
	canonical, err := jcs.CanonicalizeValue(tree)
	return string(canonical), err
}

func validateNumbers(value any) error {
	switch v := value.(type) {
	case json.Number:
		number, err := v.Int64()
		if err != nil || number > 9007199254740991 || number < -9007199254740991 {
			return fmt.Errorf("Pageforge events require safe integer numbers")
		}
	case []any:
		for _, item := range v {
			if err := validateNumbers(item); err != nil {
				return err
			}
		}
	case map[string]any:
		for _, item := range v {
			if err := validateNumbers(item); err != nil {
				return err
			}
		}
	}
	return nil
}
