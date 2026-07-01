# --- Стадия сборки: статический бинарник ---
FROM golang:1.26 AS build

WORKDIR /src

# Сначала зависимости — кэш слоёв не инвалидируется при правках кода.
COPY go.mod go.sum* ./
RUN go mod download

COPY . .

# Версия и commit пробрасываются через build-args в ldflags.
ARG VERSION=0.1.0
ARG COMMIT=unknown

# CGO выключен → полностью статический бинарник, поедет на distroless static.
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X github.com/axawys/botswain/agent/internal/version.Version=${VERSION} -X github.com/axawys/botswain/agent/internal/version.Commit=${COMMIT}" \
    -o /out/agent ./cmd/agent

# --- Стадия рантайма: минимальный образ ---
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/agent /agent

EXPOSE 8080

# Внутри контейнера биндимся на 0.0.0.0, чтобы docker run -p достучался.
# Изоляцию снаружи обеспечивает публикация на loopback хоста
# (docker run -p 127.0.0.1:PORT:PORT).
ENTRYPOINT ["/agent"]
CMD ["--host", "0.0.0.0", "--port", "8080"]
