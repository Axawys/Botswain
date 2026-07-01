package api

import (
	"encoding/json"
	"net/http"
)

type putProxiesRequest struct {
	Proxies []string `json:"proxies"`
}

// getProxiesHandler возвращает текущую конфигурацию прокси.
func (s *Server) getProxiesHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.proxies.Snapshot())
}

// putProxiesHandler принимает список прокси, проверяет их по порядку, выбирает
// первый рабочий активным и пробрасывает его новым ботам.
func (s *Server) putProxiesHandler(w http.ResponseWriter, r *http.Request) {
	var req putProxiesRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, codeInvalidSpec, "invalid proxies body")
		return
	}

	cfg := s.proxies.SetAndCheck(r.Context(), req.Proxies)

	// Активный прокси применяется к новым ботам.
	if s.bots != nil {
		s.bots.SetActiveProxy(cfg.Active)
	}

	writeJSON(w, http.StatusOK, cfg)
}
