// Package api раздаёт control-API агента (см. docs/control-api.md).
package api

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// Server держит состояние, общее для хендлеров.
type Server struct {
	startedAt time.Time
}

// NewServer создаёт сервер API. startedAt фиксируется здесь для расчёта uptime.
func NewServer() *Server {
	return &Server{startedAt: time.Now()}
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
	})

	return r
}
