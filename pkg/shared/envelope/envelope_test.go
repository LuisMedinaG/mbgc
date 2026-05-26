package envelope_test

import (
	"encoding/json"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
)

func TestNew(t *testing.T) {
	r := envelope.New("hello")
	if r.Data != "hello" {
		t.Fatalf("got %q, want %q", r.Data, "hello")
	}
}

func TestNewList_NilCoercion(t *testing.T) {
	r := envelope.NewList[string](nil, 1, 20, 0)
	if r.Data == nil {
		t.Fatal("Data should be empty slice, not nil")
	}
	b, _ := json.Marshal(r)
	if string(b) != `{"data":[],"meta":{"page":1,"limit":20,"total":0}}` {
		t.Fatalf("unexpected JSON: %s", b)
	}
}

func TestNewList_Meta(t *testing.T) {
	items := []int{1, 2, 3}
	r := envelope.NewList(items, 2, 10, 42)
	if r.Meta.Page != 2 || r.Meta.Limit != 10 || r.Meta.Total != 42 {
		t.Fatalf("unexpected meta: %+v", r.Meta)
	}
}

func TestNewError(t *testing.T) {
	r := envelope.NewError("NOT_FOUND", "game not found")
	if r.Error.Code != "NOT_FOUND" || r.Error.Message != "game not found" {
		t.Fatalf("unexpected error: %+v", r.Error)
	}
	if r.Error.Details != nil {
		t.Fatal("Details should be nil")
	}
}

func TestNewError_WithDetails(t *testing.T) {
	details := map[string]string{"field": "name", "issue": "required"}
	r := envelope.NewError("VALIDATION_FAILED", "invalid input", details)
	if r.Error.Details == nil {
		t.Fatal("Details should not be nil")
	}
}
