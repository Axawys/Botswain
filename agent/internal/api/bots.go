package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/axawys/botswain/agent/internal/bots"
)

// Максимальный размер загружаемого архива с кодом бота.
const maxCodeUpload = 64 << 20 // 64 MiB

func (s *Server) listBotsHandler(w http.ResponseWriter, r *http.Request) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}
	list, err := s.bots.List(r.Context())
	if err != nil {
		s.writeBotError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

func (s *Server) getBotHandler(w http.ResponseWriter, r *http.Request) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}
	bot, err := s.bots.Get(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		s.writeBotError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, bot)
}

func (s *Server) createBotHandler(w http.ResponseWriter, r *http.Request) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxCodeUpload)
	if err := r.ParseMultipartForm(maxCodeUpload); err != nil {
		writeError(w, http.StatusBadRequest, codeInvalidArchive, "malformed multipart body")
		return
	}

	// Спек передаётся текстовым полем `spec` с JSON внутри.
	var spec bots.Spec
	if err := json.Unmarshal([]byte(r.FormValue("spec")), &spec); err != nil {
		writeError(w, http.StatusBadRequest, codeInvalidSpec, "spec is not valid JSON")
		return
	}

	// Код — файловая часть `code` (.tar.gz).
	file, _, err := r.FormFile("code")
	if err != nil {
		writeError(w, http.StatusBadRequest, codeInvalidArchive, "missing `code` archive part")
		return
	}
	defer file.Close()
	code, err := io.ReadAll(file)
	if err != nil {
		writeError(w, http.StatusBadRequest, codeInvalidArchive, "cannot read `code` archive")
		return
	}

	bot, err := s.bots.Create(r.Context(), spec, code)
	if err != nil {
		s.writeBotError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, bot)
}

func (s *Server) startBotHandler(w http.ResponseWriter, r *http.Request) {
	s.lifecycle(w, r, s.bots.Start)
}

func (s *Server) stopBotHandler(w http.ResponseWriter, r *http.Request) {
	s.lifecycle(w, r, s.bots.Stop)
}

func (s *Server) restartBotHandler(w http.ResponseWriter, r *http.Request) {
	s.lifecycle(w, r, s.bots.Restart)
}

// lifecycle обслуживает start/stop/restart: общий каркас, отличается действием.
func (s *Server) lifecycle(w http.ResponseWriter, r *http.Request, action func(ctx context.Context, id string) (bots.Bot, error)) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}
	bot, err := action(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		s.writeBotError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, bot)
}

func (s *Server) deleteBotHandler(w http.ResponseWriter, r *http.Request) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}
	if err := s.bots.Delete(r.Context(), chi.URLParam(r, "id")); err != nil {
		s.writeBotError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// writeBotError сопоставляет ошибки менеджера с кодами control-API.
func (s *Server) writeBotError(w http.ResponseWriter, err error) {
	switch {
	case bots.IsDockerUnavailable(err):
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
	case errors.Is(err, bots.ErrNotFound):
		writeError(w, http.StatusNotFound, codeBotNotFound, "bot not found")
	case errors.Is(err, bots.ErrNameConflict):
		writeError(w, http.StatusConflict, codeBotNameConflict, "bot name already in use")
	case errors.Is(err, bots.ErrInvalidSpec):
		writeError(w, http.StatusBadRequest, codeInvalidSpec, "invalid spec")
	case errors.Is(err, bots.ErrInvalidArchive):
		writeError(w, http.StatusBadRequest, codeInvalidArchive, "invalid code archive")
	case errors.Is(err, bots.ErrEntrypointNotFound):
		writeError(w, http.StatusUnprocessableEntity, codeEntrypointNotFound, "entrypoint not found in archive")
	case errors.Is(err, bots.ErrInstallFailed):
		writeError(w, http.StatusInternalServerError, codeInstallFailed, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, codeInternal, "internal error")
	}
}
