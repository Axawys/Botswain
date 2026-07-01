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
func (s *Server) healthHandler(w http.ResponseWriter, _ *http.Request) {
	now := time.Now().UTC()
	writeJSON(w, http.StatusOK, healthResponse{
		// В v0 агент всегда готов, как только роутер отвечает. Проверка
		// критичных зависимостей (docker.sock) появится в следующих milestone'ах.
		Status:        "ok",
		Version:       version.Version,
		Commit:        version.Commit,
		UptimeSeconds: int64(now.Sub(s.startedAt).Seconds()),
		Time:          now.Format(time.RFC3339),
	})
}
