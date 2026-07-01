// Package api раздаёт control-API агента (см. docs/control-api.md).
package api

import (
	"log"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/axawys/botswain/agent/internal/bots"
	"github.com/axawys/botswain/agent/internal/proxy"
)

// Server держит состояние, общее для хендлеров.
type Server struct {
	startedAt time.Time
	// bots может быть nil, если Docker-клиент не удалось инициализировать —
	// тогда health отдаёт not_ready, а эндпоинты ботов — docker_unavailable.
	bots    *bots.Manager
	proxies *proxy.Manager
}

// NewServer создаёт сервер API. startedAt фиксируется здесь для расчёта uptime.
func NewServer() *Server {
	mgr, err := bots.NewManager()
	if err != nil {
		log.Printf("не удалось инициализировать Docker-клиент: %v", err)
	}
	return &Server{
		startedAt: time.Now(),
		bots:      mgr,
		proxies:   proxy.NewManager(),
	}
}

// Handler собирает http.Handler со всеми маршрутами и middleware.
func (s *Server) Handler() http.Handler {
	r := chi.NewRouter()

	// Базовые middleware: request-id для трассировки и восстановление после
	// паники в хендлере (Recoverer отдаёт голый 500 — для необработанной паники
	// этого достаточно; штатные ошибки хендлеры возвращают через writeError).
	r.Use(middleware.RequestID)
	r.Use(middleware.Recoverer)

	// Единый формат для системных ответов роутера.
	r.NotFound(notFoundHandler)
	r.MethodNotAllowed(methodNotAllowedHandler)

	// Все эндпоинты живут под префиксом версии API.
	r.Route("/v0", func(r chi.Router) {
		r.Get("/health", s.healthHandler)

		r.Get("/proxies", s.getProxiesHandler)
		r.Put("/proxies", s.putProxiesHandler)

		r.Route("/bots", func(r chi.Router) {
			r.Get("/", s.listBotsHandler)
			r.Post("/", s.createBotHandler)
			r.Route("/{id}", func(r chi.Router) {
				r.Get("/", s.getBotHandler)
				r.Delete("/", s.deleteBotHandler)
				r.Post("/start", s.startBotHandler)
				r.Post("/stop", s.stopBotHandler)
				r.Post("/restart", s.restartBotHandler)
				r.Get("/metrics", s.botMetricsHandler)
				r.Get("/logs", s.botLogsHandler)
			})
		})
	})

	return r
}
