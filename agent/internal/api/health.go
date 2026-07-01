package api

import (
	"net/http"
	"time"

	"github.com/axawys/botswain/agent/internal/version"
)

// healthResponse — тело ответа GET /v0/health (см. docs/control-api.md).
type healthResponse struct {
	Status        string `json:"status"`
	Version       string `json:"version"`
	Commit        string `json:"commit"`
	UptimeSeconds int64  `json:"uptime_seconds"`
	Time          string `json:"time"`
}

// healthHandler возвращает состояние агента. Дёшев и без побочных эффектов —
// рассчитан на health-check при bootstrap и на периодический polling туннеля.
//
// Начиная с M2 готовность включает доступность Docker: если демон недоступен,
// агент отвечает 503 not_ready.
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	now := time.Now().UTC()

	if s.bots == nil || s.bots.Ping(r.Context()) != nil {
		writeError(w, http.StatusServiceUnavailable, codeNotReady,
			"docker daemon is unavailable")
		return
	}

	writeJSON(w, http.StatusOK, healthResponse{
		Status:        "ok",
		Version:       version.Version,
		Commit:        version.Commit,
		UptimeSeconds: int64(now.Sub(s.startedAt).Seconds()),
		Time:          now.Format(time.RFC3339),
	})
}
