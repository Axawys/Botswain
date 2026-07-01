// Command agent — control-API агент Botswain.
// Биндится на loopback, публично в сеть не торчит (см. docs/architecture.md).
package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/axawys/botswain/agent/internal/api"
	"github.com/axawys/botswain/agent/internal/version"
)

func main() {
	// Порт: флаг --port имеет приоритет над env BOTSWAIN_PORT, затем дефолт 8080.
	defaultPort := 8080
	if env := os.Getenv("BOTSWAIN_PORT"); env != "" {
		if p, err := strconv.Atoi(env); err == nil {
			defaultPort = p
		} else {
			log.Fatalf("invalid BOTSWAIN_PORT %q: %v", env, err)
		}
	}
	port := flag.Int("port", defaultPort, "TCP-порт control-API (loopback)")
	// host по умолчанию 127.0.0.1 — безопасно для прямого локального запуска и
	// соответствует контракту. Внутри контейнера нужен 0.0.0.0, чтобы проброс
	// docker run -p 127.0.0.1:PORT:PORT достучался до агента; это задаёт
	// Dockerfile (CMD --host 0.0.0.0). Изоляцию снаружи обеспечивает сам -p.
	host := flag.String("host", "127.0.0.1", "адрес биндинга")
	flag.Parse()

	addr := net.JoinHostPort(*host, strconv.Itoa(*port))

	srv := &http.Server{
		Addr:              addr,
		Handler:           api.NewServer().Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Грациозная остановка по SIGINT/SIGTERM.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("botswain agent %s (%s) слушает %s", version.Version, version.Commit, addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("http server: %v", err)
		}
	}()

	<-ctx.Done()
	log.Print("получен сигнал остановки, завершаюсь…")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("graceful shutdown: %v", err)
	}
}
