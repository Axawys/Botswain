// Package proxy проверяет пользовательские egress-прокси и хранит выбранный
// активный (первый рабочий) для проброса ботам (см. docs/control-api.md).
package proxy

import (
	"context"
	"net/http"
	"net/url"
	"sync"
	"time"
)

// Куда проверяем доступность — публичный вход Telegram Bot API.
const probeTarget = "https://api.telegram.org"

// Result — итог проверки одного прокси.
type Result struct {
	URL string `json:"url"`
	OK  bool   `json:"ok"`
}

// Config — снимок состояния прокси: результаты проверки и активный прокси.
type Config struct {
	Results []Result `json:"results"`
	Active  string   `json:"active"`
}

// Manager хранит список прокси, результаты проверки и активный прокси.
type Manager struct {
	mu      sync.RWMutex
	results []Result
	active  string
}

func NewManager() *Manager {
	return &Manager{results: []Result{}}
}

// SetAndCheck проверяет прокси по порядку, выбирает первый рабочий активным и
// запоминает результаты. Пустой список сбрасывает конфигурацию.
func (m *Manager) SetAndCheck(ctx context.Context, urls []string) Config {
	results := make([]Result, 0, len(urls))
	active := ""
	for _, u := range urls {
		ok := checkProxy(ctx, u)
		results = append(results, Result{URL: u, OK: ok})
		if ok && active == "" {
			active = u
		}
	}

	m.mu.Lock()
	m.results = results
	m.active = active
	m.mu.Unlock()

	return Config{Results: results, Active: active}
}

// Snapshot возвращает текущую конфигурацию.
func (m *Manager) Snapshot() Config {
	m.mu.RLock()
	defer m.mu.RUnlock()
	// Копируем срез, чтобы наружу не утёк внутренний.
	results := make([]Result, len(m.results))
	copy(results, m.results)
	return Config{Results: results, Active: m.active}
}

// Active возвращает активный прокси (или пустую строку).
func (m *Manager) Active() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.active
}

// checkProxy пытается достучаться до api.telegram.org через прокси. Успех —
// любой полученный HTTP-ответ (значит, соединение через прокси установлено).
// net/http Transport поддерживает http/https/socks5 прокси нативно.
func checkProxy(ctx context.Context, raw string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return false
	}

	tr := &http.Transport{
		Proxy:                 http.ProxyURL(u),
		TLSHandshakeTimeout:   6 * time.Second,
		ResponseHeaderTimeout: 6 * time.Second,
		DisableKeepAlives:     true,
	}
	client := &http.Client{Transport: tr, Timeout: 8 * time.Second}

	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, probeTarget, nil)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	_ = resp.Body.Close()
	return true
}
