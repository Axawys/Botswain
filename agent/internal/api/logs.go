package api

import (
	"context"
	"net/http"

	"github.com/coder/websocket"
	"github.com/docker/docker/pkg/stdcopy"
	"github.com/go-chi/chi/v5"
)

// botLogsHandler стримит логи бота по WebSocket (см. docs/control-api.md).
func (s *Server) botLogsHandler(w http.ResponseWriter, r *http.Request) {
	if s.bots == nil {
		writeError(w, http.StatusServiceUnavailable, codeDockerUnavailable, "docker daemon is unavailable")
		return
	}
	id := chi.URLParam(r, "id")

	// Проверяем существование бота ДО апгрейда, чтобы отдать честный HTTP-код.
	if _, err := s.bots.Get(r.Context(), id); err != nil {
		s.writeBotError(w, err)
		return
	}

	// Аутентификация — сам SSH-туннель, поэтому Origin не проверяем.
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	defer c.Close(websocket.StatusNormalClosure, "")

	// Контекст отменяется, когда клиент закрывает соединение — тогда и поток
	// логов Docker завершится, а StdCopy вернётся.
	ctx := c.CloseRead(r.Context())

	logs, err := s.bots.Logs(ctx, id, "200")
	if err != nil {
		c.Close(websocket.StatusInternalError, "cannot open logs")
		return
	}
	defer logs.Close()

	writer := &wsLogWriter{ctx: ctx, conn: c}
	// Docker отдаёт stdout+stderr мультиплексированными — StdCopy убирает
	// служебные заголовки и склеивает оба потока в один текстовый.
	_, _ = stdcopy.StdCopy(writer, writer, logs)
}

// wsLogWriter превращает записи потока логов в текстовые WebSocket-фреймы.
type wsLogWriter struct {
	ctx  context.Context
	conn *websocket.Conn
}

func (w *wsLogWriter) Write(p []byte) (int, error) {
	if err := w.conn.Write(w.ctx, websocket.MessageText, p); err != nil {
		return 0, err
	}
	return len(p), nil
}
