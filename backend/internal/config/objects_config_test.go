package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestContentObjectConfiguration(t *testing.T) {
	defaults, err := os.ReadFile(filepath.Join("..", "..", "..", "pageforge.config.json"))
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err = os.WriteFile(filepath.Join(root, "pageforge.config.json"), defaults, 0600); err != nil {
		t.Fatal(err)
	}
	c, err := Load(root)
	if err != nil || c.Storage.RevisionFormat != "objects-v1" ||
		c.Storage.ObjectCount != 100000 || c.Storage.InlineObjectBytes != 65536 ||
		c.Storage.ObjectCatalogMiB != 8 {
		t.Fatal("object defaults", err)
	}
	invalid := []string{
		`{"storage":{"revisionFormat":"unknown"}}`,
		`{"storage":{"objectCount":0}}`,
		`{"storage":{"objectCount":1000001}}`,
		`{"storage":{"inlineObjectBytes":-1}}`,
		`{"storage":{"inlineObjectBytes":65537}}`,
		`{"storage":{"objectCatalogMiB":0}}`,
		`{"storage":{"objectCatalogMiB":33}}`,
	}
	for _, override := range invalid {
		if err = os.WriteFile(filepath.Join(root, "pageforge.config.local.json"), []byte(override), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err = Load(root); err == nil {
			t.Fatal("invalid object configuration accepted", override)
		}
	}
	if err = os.WriteFile(filepath.Join(root, "pageforge.config.local.json"), []byte(`{"storage":{"revisionFormat":"legacy","objectCount":32}}`), 0600); err != nil {
		t.Fatal(err)
	}
	c, err = Load(root)
	if err != nil || c.Storage.RevisionFormat != "legacy" || c.Storage.ObjectCount != 32 {
		t.Fatal("override", err)
	}
}
