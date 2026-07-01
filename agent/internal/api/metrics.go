package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func (s *Server) botMetricsHandler(w http.ResponseWriter, r *http.Request) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}
	metrics, err := s.bots.Metrics(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		s.writeBotError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, metrics)
}
