package gobackend

import (
	"testing"

	"github.com/dop251/goja"
)

func TestParseExtensionURLHandleValueCapturesID(t *testing.T) {
	vm := goja.New()
	value, err := vm.RunString(`({
		type: "playlist",
		id: "37i9dQZF1DXcBWIGoYBM5M",
		name: "Discover Weekly",
		tracks: []
	})`)
	if err != nil {
		t.Fatalf("RunString: %v", err)
	}

	result, err := parseExtensionURLHandleValue(vm, value)
	if err != nil {
		t.Fatalf("parseExtensionURLHandleValue: %v", err)
	}
	if result.Type != "playlist" {
		t.Fatalf("Type = %q", result.Type)
	}
	if result.ID != "37i9dQZF1DXcBWIGoYBM5M" {
		t.Fatalf("ID = %q, want the playlist id from the handler result", result.ID)
	}
	if result.Name != "Discover Weekly" {
		t.Fatalf("Name = %q", result.Name)
	}
}

func TestParseExtensionURLHandleValueOmitsIDWhenAbsent(t *testing.T) {
	vm := goja.New()
	// Track/album/artist results carry their own ID inside their nested
	// metadata, so a handler that omits the top-level "id" (as these do
	// today) must not surface a stale or zero-value ID.
	value, err := vm.RunString(`({ type: "track", name: "A Track" })`)
	if err != nil {
		t.Fatalf("RunString: %v", err)
	}

	result, err := parseExtensionURLHandleValue(vm, value)
	if err != nil {
		t.Fatalf("parseExtensionURLHandleValue: %v", err)
	}
	if result.ID != "" {
		t.Fatalf("ID = %q, want empty when the handler result has none", result.ID)
	}
}
