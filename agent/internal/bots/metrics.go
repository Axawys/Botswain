package bots

import (
	"context"
	"encoding/json"
	"io"

	"github.com/docker/docker/api/types/container"
)

// Metrics — снапшот потребления ресурсов ботом (см. docs/control-api.md).
type Metrics struct {
	CPUPercent    float64 `json:"cpu_percent"`
	MemoryUsedMB  float64 `json:"memory_used_mb"`
	MemoryLimitMB float64 `json:"memory_limit_mb"`
	MemoryPercent float64 `json:"memory_percent"`
}

// dockerStats — минимальная проекция ответа Docker stats, чтобы не зависеть от
// конкретных типов SDK.
type dockerStats struct {
	CPUStats    cpuStats    `json:"cpu_stats"`
	PreCPUStats cpuStats    `json:"precpu_stats"`
	MemoryStats memoryStats `json:"memory_stats"`
}

type cpuStats struct {
	CPUUsage struct {
		TotalUsage uint64 `json:"total_usage"`
	} `json:"cpu_usage"`
	SystemUsage uint64 `json:"system_cpu_usage"`
	OnlineCPUs  uint32 `json:"online_cpus"`
}

type memoryStats struct {
	Usage uint64            `json:"usage"`
	Limit uint64            `json:"limit"`
	Stats map[string]uint64 `json:"stats"`
}

// Metrics возвращает снапшот CPU/RAM бота.
//
// CPU% считается по дельте двух подряд замеров: открываем поток статистики,
// пропускаем первый сэмпл (в нём precpu пустой) и берём второй, где Docker уже
// заполнил precpu предыдущим значением.
func (m *Manager) Metrics(ctx context.Context, id string) (Metrics, error) {
	if err := m.ensureExists(ctx, id); err != nil {
		return Metrics{}, err
	}

	resp, err := m.cli.ContainerStats(ctx, containerName(id), true)
	if err != nil {
		return Metrics{}, err
	}
	defer resp.Body.Close()

	dec := json.NewDecoder(resp.Body)
	var s dockerStats
	// Первый сэмпл — прайминг (precpu ещё нулевой).
	if err := dec.Decode(&s); err != nil {
		return Metrics{}, err
	}
	// Второй сэмпл — с корректным precpu.
	if err := dec.Decode(&s); err != nil {
		if err == io.EOF {
			// Контейнер остановлен: поток мог отдать только один сэмпл.
			// Возвращаем то, что есть (CPU% выйдет 0).
			return computeMetrics(s), nil
		}
		return Metrics{}, err
	}
	return computeMetrics(s), nil
}

// computeMetrics переводит сырые счётчики Docker в проценты и мегабайты.
func computeMetrics(s dockerStats) Metrics {
	const mib = 1024 * 1024

	cpuDelta := float64(s.CPUStats.CPUUsage.TotalUsage) -
		float64(s.PreCPUStats.CPUUsage.TotalUsage)
	systemDelta := float64(s.CPUStats.SystemUsage) -
		float64(s.PreCPUStats.SystemUsage)

	cpuPercent := 0.0
	if systemDelta > 0 && cpuDelta > 0 {
		cpus := float64(s.CPUStats.OnlineCPUs)
		if cpus == 0 {
			cpus = 1
		}
		cpuPercent = (cpuDelta / systemDelta) * cpus * 100
	}

	// Из usage вычитаем страничный кэш (inactive_file) — так делает docker stats.
	used := float64(s.MemoryStats.Usage)
	if v, ok := s.MemoryStats.Stats["inactive_file"]; ok {
		used -= float64(v)
	}
	if used < 0 {
		used = 0
	}
	limit := float64(s.MemoryStats.Limit)

	memPercent := 0.0
	if limit > 0 {
		memPercent = used / limit * 100
	}

	return Metrics{
		CPUPercent:    cpuPercent,
		MemoryUsedMB:  used / mib,
		MemoryLimitMB: limit / mib,
		MemoryPercent: memPercent,
	}
}

// Logs открывает поток логов бота (мультиплексированный stdout+stderr Docker).
// Вызывающий обязан закрыть поток. tail — сколько последних строк отдать сразу.
func (m *Manager) Logs(ctx context.Context, id string, tail string) (io.ReadCloser, error) {
	if err := m.ensureExists(ctx, id); err != nil {
		return nil, err
	}
	return m.cli.ContainerLogs(ctx, containerName(id), container.LogsOptions{
		ShowStdout: true,
		ShowStderr: true,
		Follow:     true,
		Tail:       tail,
	})
}
