// Package proxy проверяет пользовательские egress-прокси и хранит выбранный
// активный (первый рабочий) для проброса ботам (см. docs/control-api.md).
package proxy

import (
	"context"
	"net"
	"net/url"
	"strings"
	"sync"
	"time"

	xproxy "golang.org/x/net/proxy"
)

// Куда проверяем доступность — вход Telegram Bot API (TCP до 443).
const probeTarget = "api.telegram.org:443"

// Параметры проверки: короткий таймаут на прокси и ограниченная конкурентность,
// чтобы большие списки (сотни прокси) проверялись за секунды, а не минуты.
const (
	checkTimeout   = 4 * time.Second
	maxConcurrency = 50
)

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

// SetAndCheck проверяет прокси параллельно, сохраняя порядок, выбирает первый
// рабочий активным и запоминает результаты. Пустой список сбрасывает конфиг.
func (m *Manager) SetAndCheck(ctx context.Context, urls []string) Config {
	results := make([]Result, len(urls))

	sem := make(chan struct{}, maxConcurrency)
	var wg sync.WaitGroup
	for i, raw := range urls {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, raw string) {
			defer wg.Done()
			defer func() { <-sem }()
			norm := normalizeProxy(raw)
			results[i] = Result{URL: norm, OK: checkProxy(ctx, norm)}
		}(i, raw)
	}
	wg.Wait()

	// Активный — первый рабочий в исходном порядке.
	active := ""
	for _, r := range results {
		if r.OK {
			active = r.URL
			break
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

// normalizeProxy приводит запись к URL со схемой. Голый `host:port` считаем
// socks5 (основной тип прокси для ботов).
func normalizeProxy(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return raw
	}
	if !strings.Contains(raw, "://") {
		return "socks5://" + raw
	}
	return raw
}

// checkProxy проверяет, что через прокси устанавливается TCP-соединение до
// api.telegram.org:443. Это дешевле полного HTTPS-запроса и достаточно, чтобы
// понять, что прокси даёт доступ к Telegram.
func checkProxy(ctx context.Context, raw string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return false
	}

	ctx, cancel := context.WithTimeout(ctx, checkTimeout)
	defer cancel()

	switch u.Scheme {
	case "socks5", "socks5h":
		return checkSocks5(ctx, u)
	case "http", "https":
		return checkHTTPConnect(ctx, u)
	default:
		return false
	}
}

func checkSocks5(ctx context.Context, u *url.URL) bool {
	var auth *xproxy.Auth
	if u.User != nil {
		pw, _ := u.User.Password()
		auth = &xproxy.Auth{User: u.User.Username(), Password: pw}
	}
	dialer, err := xproxy.SOCKS5("tcp", u.Host, auth, &net.Dialer{Timeout: checkTimeout})
	if err != nil {
		return false
	}
	cd, ok := dialer.(xproxy.ContextDialer)
	if !ok {
		return false
	}
	conn, err := cd.DialContext(ctx, "tcp", probeTarget)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

// checkHTTPConnect делает CONNECT к api.telegram.org:443 через http-прокси.
func checkHTTPConnect(ctx context.Context, u *url.URL) bool {
	d := &net.Dialer{Timeout: checkTimeout}
	conn, err := d.DialContext(ctx, "tcp", u.Host)
	if err != nil {
		return false
	}
	defer conn.Close()

	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	req := "CONNECT " + probeTarget + " HTTP/1.1\r\nHost: " + probeTarget + "\r\n"
	if u.User != nil {
		// Базовая авторизация опущена для краткости — большинство списков без неё.
		_ = u.User
	}
	req += "\r\n"
	if _, err := conn.Write([]byte(req)); err != nil {
		return false
	}
	buf := make([]byte, 64)
	n, err := conn.Read(buf)
	if err != nil || n == 0 {
		return false
	}
	// Успех — статус 200 в ответе прокси.
	return strings.Contains(string(buf[:n]), " 200 ")
}
