// Package vax implements the exact wire format of vax-sdk 1.0.0.
// That encoder escapes every non-ASCII UTF-16 code unit; ordinary JSON is different.
package vax

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"unicode/utf16"
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
	var out strings.Builder
	err = encode(&out, tree)
	return out.String(), err
}

func encode(out *strings.Builder, value any) error {
	switch v := value.(type) {
	case nil:
		out.WriteString("null")
	case bool:
		out.WriteString(strconv.FormatBool(v))
	case string:
		quoted(out, v)
	case json.Number:
		// Pageforge envelopes contain only safe integer timestamps, never floating point.
		number, err := v.Int64()
		if err != nil || number > 9007199254740991 || number < -9007199254740991 {
			return fmt.Errorf("VAX 協定僅接受安全整數")
		}
		out.WriteString(strconv.FormatInt(number, 10))
	case []any:
		out.WriteByte('[')
		for i, item := range v {
			if i > 0 {
				out.WriteByte(',')
			}
			if err := encode(out, item); err != nil {
				return err
			}
		}
		out.WriteByte(']')
	case map[string]any:
		keys := make([]string, 0, len(v))
		for key := range v {
			keys = append(keys, key)
		}
		sort.Slice(keys, func(i, j int) bool {
			a, b := utf16.Encode([]rune(keys[i])), utf16.Encode([]rune(keys[j]))
			for k := 0; k < len(a) && k < len(b); k++ {
				if a[k] != b[k] {
					return a[k] < b[k]
				}
			}
			return len(a) < len(b)
		})
		out.WriteByte('{')
		for i, key := range keys {
			if i > 0 {
				out.WriteByte(',')
			}
			quoted(out, key)
			out.WriteByte(':')
			if err := encode(out, v[key]); err != nil {
				return err
			}
		}
		out.WriteByte('}')
	default:
		return fmt.Errorf("不支援的 VAX 值 %T", value)
	}
	return nil
}

func quoted(out *strings.Builder, value string) {
	out.WriteByte('"')
	for _, code := range utf16.Encode([]rune(value)) {
		switch code {
		case '"':
			out.WriteString(`\"`)
		case '\\':
			out.WriteString(`\\`)
		case '\b':
			out.WriteString(`\b`)
		case '\f':
			out.WriteString(`\f`)
		case '\n':
			out.WriteString(`\n`)
		case '\r':
			out.WriteString(`\r`)
		case '\t':
			out.WriteString(`\t`)
		default:
			if code < 0x20 || code > 0x7e {
				fmt.Fprintf(out, `\u%04x`, code)
			} else {
				out.WriteByte(byte(code))
			}
		}
	}
	out.WriteByte('"')
}
