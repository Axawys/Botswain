package proxy

import (
	"context"
	"testing"
)

func TestCheckProxyRejectsBadInput(t *testing.T) {
	ctx := context.Background()

	// Мусорная строка — не URL.
	if checkProxy(ctx, "not a proxy") {
		t.Error("мусорный прокси не должен считаться рабочим")
	}
	// Синтаксически валидный, но заведомо недоступный адрес.
	if checkProxy(ctx, "http://127.0.0.1:1") {
		t.Error("недоступный прокси не должен считаться рабочим")
	}
}

func TestSetAndCheckSelectsNoneWhenAllFail(t *testing.T) {
	m := NewManager()
	cfg := m.SetAndCheck(context.Background(), []string{"http://127.0.0.1:1"})
	if cfg.Active != "" {
		t.Errorf("active должен быть пустым, получено %q", cfg.Active)
	}
	if len(cfg.Results) != 1 || cfg.Results[0].OK {
		t.Errorf("ожидался один нерабочий результат, получено %+v", cfg.Results)
	}
	if m.Active() != "" {
		t.Error("Active() должен быть пустым")
	}
}

func TestSetAndCheckEmptyResets(t *testing.T) {
	m := NewManager()
	cfg := m.SetAndCheck(context.Background(), nil)
	if len(cfg.Results) != 0 || cfg.Active != "" {
		t.Errorf("пустой список должен давать пустую конфигурацию, получено %+v", cfg)
	}
}
