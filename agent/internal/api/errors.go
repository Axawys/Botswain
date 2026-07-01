package api

import (
	"encoding/json"
	"net/http"
)

// apiError — единый конверт ошибки control-API (см. docs/control-api.md).
type apiError struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

// Стабильные машиночитаемые коды ошибок v0.
const (
	codeNotFound         = "not_found"
	codeMethodNotAllowed = "method_not_allowed"
	codeInternal         = "internal"
	codeNotReady         = "not_ready"
)

// writeJSON сериализует v в тело ответа с заданным статусом.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	// Ошибку кодирования логировать здесь нечем и некуда откатывать —
	// заголовки уже отправлены. Молча игнорируем: тело просто оборвётся.
	_ = json.NewEncoder(w).Encode(v)
}

// writeError отправляет ошибку в едином формате конверта.
func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, apiError{Error: errorBody{Code: code, Message: message}})
}

// notFoundHandler — обработчик неизвестных путей.
func notFoundHandler(w http.ResponseWriter, _ *http.Request) {
	writeError(w, http.StatusNotFound, codeNotFound, "unknown path")
}

// methodNotAllowedHandler — обработчик неверного метода для известного пути.
func methodNotAllowedHandler(w http.ResponseWriter, _ *http.Request) {
	writeError(w, http.StatusMethodNotAllowed, codeMethodNotAllowed, "method not allowed")
}
