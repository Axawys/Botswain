// Package bots управляет жизненным циклом ботов как соседних Docker-контейнеров
// (docker-out-of-docker). Источник правды о ботах — сами контейнеры: метаданные
// хранятся в labels, отдельной БД нет (см. docs/architecture.md).
package bots

import "errors"

// Имена и пути, общие для рантайм-модели ботов.
const (
	BaseImage       = "python:3.12-slim"
	containerPrefix = "botswain-bot-"
	appDir          = "/app"
	depsDir         = "/app/.deps"
)

// Labels контейнера, в которых живут метаданные бота.
const (
	labelManaged    = "botswain.managed"
	labelID         = "botswain.bot.id"
	labelName       = "botswain.bot.name"
	labelEntrypoint = "botswain.bot.entrypoint"
	labelMemoryMB   = "botswain.bot.memory_mb"
	labelCPUs       = "botswain.bot.cpus"
	labelCreatedAt  = "botswain.bot.created_at"
)

// Дефолты лимитов, если клиент их не задал.
const (
	defaultMemoryMB = 256
	defaultCPUs     = 0.5
)

// Limits — лимиты ресурсов бота.
type Limits struct {
	MemoryMB int     `json:"memory_mb"`
	CPUs     float64 `json:"cpus"`
}

// Spec — запрос на создание бота (часть `spec` в multipart).
type Spec struct {
	Name       string `json:"name"`
	Entrypoint string `json:"entrypoint"`
	Limits     Limits `json:"limits"`
}

// Bot — представление бота в control-API (см. docs/control-api.md).
type Bot struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Entrypoint string `json:"entrypoint"`
	Status     string `json:"status"`
	Limits     Limits `json:"limits"`
	Image      string `json:"image"`
	CreatedAt  string `json:"created_at"`
}

// Сентинел-ошибки. Слой api сопоставляет их с кодами control-API.
var (
	ErrNotFound           = errors.New("bot not found")
	ErrNameConflict       = errors.New("bot name conflict")
	ErrInvalidSpec        = errors.New("invalid spec")
	ErrInvalidArchive     = errors.New("invalid archive")
	ErrEntrypointNotFound = errors.New("entrypoint not found")
	ErrInstallFailed      = errors.New("dependency install failed")
)
