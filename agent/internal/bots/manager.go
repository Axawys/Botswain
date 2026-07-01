package bots

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/strslice"
	"github.com/docker/docker/api/types/volume"
	"github.com/docker/docker/client"
)

// Manager инкапсулирует работу с Docker-демоном для управления ботами.
type Manager struct {
	cli *client.Client
}

// NewManager создаёт менеджер, подключаясь к Docker через переменные окружения
// (в контейнере агента — через смонтированный /var/run/docker.sock).
func NewManager() (*Manager, error) {
	cli, err := client.NewClientWithOpts(
		client.FromEnv,
		client.WithAPIVersionNegotiation(),
	)
	if err != nil {
		return nil, err
	}
	return &Manager{cli: cli}, nil
}

// Ping проверяет доступность Docker-демона (используется в health-check).
func (m *Manager) Ping(ctx context.Context) error {
	_, err := m.cli.Ping(ctx)
	return err
}

// IsDockerUnavailable сообщает, что ошибка вызвана недоступностью Docker-демона.
func IsDockerUnavailable(err error) bool {
	return client.IsErrConnectionFailed(err)
}

// List возвращает всех ботов, которыми управляет Botswain.
func (m *Manager) List(ctx context.Context) ([]Bot, error) {
	summaries, err := m.cli.ContainerList(ctx, container.ListOptions{
		All:     true,
		Filters: filters.NewArgs(filters.Arg("label", labelManaged+"=true")),
	})
	if err != nil {
		return nil, err
	}
	bots := make([]Bot, 0, len(summaries))
	for _, s := range summaries {
		bots = append(bots, fromSummary(s))
	}
	return bots, nil
}

// Get возвращает бота по id или ErrNotFound.
func (m *Manager) Get(ctx context.Context, id string) (Bot, error) {
	summaries, err := m.cli.ContainerList(ctx, container.ListOptions{
		All: true,
		Filters: filters.NewArgs(
			filters.Arg("label", labelManaged+"=true"),
			filters.Arg("label", labelID+"="+id),
		),
	})
	if err != nil {
		return Bot{}, err
	}
	if len(summaries) == 0 {
		return Bot{}, ErrNotFound
	}
	return fromSummary(summaries[0]), nil
}

// Start запускает остановленного бота и возвращает его актуальное состояние.
func (m *Manager) Start(ctx context.Context, id string) (Bot, error) {
	if err := m.ensureExists(ctx, id); err != nil {
		return Bot{}, err
	}
	if err := m.cli.ContainerStart(ctx, containerName(id), container.StartOptions{}); err != nil {
		return Bot{}, err
	}
	return m.Get(ctx, id)
}

// Stop останавливает бота.
func (m *Manager) Stop(ctx context.Context, id string) (Bot, error) {
	if err := m.ensureExists(ctx, id); err != nil {
		return Bot{}, err
	}
	if err := m.cli.ContainerStop(ctx, containerName(id), container.StopOptions{}); err != nil {
		return Bot{}, err
	}
	return m.Get(ctx, id)
}

// Restart перезапускает бота.
func (m *Manager) Restart(ctx context.Context, id string) (Bot, error) {
	if err := m.ensureExists(ctx, id); err != nil {
		return Bot{}, err
	}
	if err := m.cli.ContainerRestart(ctx, containerName(id), container.StopOptions{}); err != nil {
		return Bot{}, err
	}
	return m.Get(ctx, id)
}

// Delete удаляет контейнер бота и его volume.
func (m *Manager) Delete(ctx context.Context, id string) error {
	if err := m.ensureExists(ctx, id); err != nil {
		return err
	}
	if err := m.cli.ContainerRemove(ctx, containerName(id), container.RemoveOptions{Force: true}); err != nil {
		return err
	}
	// Volume именованный — удаляем отдельно (force на случай, если он ещё
	// числится используемым).
	return m.cli.VolumeRemove(ctx, volumeName(id), true)
}

// Create создаёт и запускает нового бота из спека и архива с кодом (.tar.gz).
func (m *Manager) Create(ctx context.Context, spec Spec, codeTarGz []byte) (Bot, error) {
	spec, err := normalizeSpec(spec)
	if err != nil {
		return Bot{}, err
	}

	// Имя должно быть уникальным среди ботов.
	if err := m.assertNameFree(ctx, spec.Name); err != nil {
		return Bot{}, err
	}

	// Распаковываем архив в плоский tar, проверяя наличие entrypoint.
	codeTar, hasRequirements, err := prepareCode(codeTarGz, spec.Entrypoint)
	if err != nil {
		return Bot{}, err
	}

	id, err := newID()
	if err != nil {
		return Bot{}, err
	}
	createdAt := time.Now().UTC().Format(time.RFC3339)

	if err := m.ensureImage(ctx, BaseImage); err != nil {
		return Bot{}, err
	}

	// Volume с кодом и зависимостями.
	if _, err := m.cli.VolumeCreate(ctx, volume.CreateOptions{
		Name:   volumeName(id),
		Labels: map[string]string{labelManaged: "true", labelID: id},
	}); err != nil {
		return Bot{}, err
	}

	// Наполняем volume через временный installer-контейнер: копируем код и,
	// если есть requirements.txt, один раз ставим зависимости в /app/.deps.
	if err := m.provisionVolume(ctx, id, codeTar, hasRequirements); err != nil {
		// Прибираем volume, чтобы не копить мусор при неудаче.
		_ = m.cli.VolumeRemove(ctx, volumeName(id), true)
		return Bot{}, err
	}

	// Контейнер бота.
	if err := m.createBotContainer(ctx, id, spec, createdAt); err != nil {
		_ = m.cli.VolumeRemove(ctx, volumeName(id), true)
		return Bot{}, err
	}
	if err := m.cli.ContainerStart(ctx, containerName(id), container.StartOptions{}); err != nil {
		return Bot{}, err
	}

	return m.Get(ctx, id)
}

// --- внутренние помощники ---

func (m *Manager) ensureExists(ctx context.Context, id string) error {
	_, err := m.Get(ctx, id)
	return err
}

func (m *Manager) assertNameFree(ctx context.Context, name string) error {
	existing, err := m.List(ctx)
	if err != nil {
		return err
	}
	for _, b := range existing {
		if b.Name == name {
			return ErrNameConflict
		}
	}
	return nil
}

// ensureImage тянет образ, если его ещё нет локально.
func (m *Manager) ensureImage(ctx context.Context, ref string) error {
	imgs, err := m.cli.ImageList(ctx, image.ListOptions{
		Filters: filters.NewArgs(filters.Arg("reference", ref)),
	})
	if err != nil {
		return err
	}
	if len(imgs) > 0 {
		return nil
	}
	rc, err := m.cli.ImagePull(ctx, ref, image.PullOptions{})
	if err != nil {
		return err
	}
	defer rc.Close()
	// Дочитываем ответ до конца — иначе pull не завершится.
	_, err = io.Copy(io.Discard, rc)
	return err
}

// provisionVolume копирует код в volume и ставит зависимости.
func (m *Manager) provisionVolume(ctx context.Context, id string, codeTar []byte, hasRequirements bool) error {
	installerName := containerName(id) + "-install"

	// Команда installer'а ставит зависимости только при наличии requirements.txt.
	script := "true"
	if hasRequirements {
		script = fmt.Sprintf(
			"pip install --no-cache-dir --target %s -r %s/requirements.txt",
			depsDir, appDir,
		)
	}

	resp, err := m.cli.ContainerCreate(ctx,
		&container.Config{
			Image:      BaseImage,
			Cmd:        strslice.StrSlice{"sh", "-c", script},
			WorkingDir: appDir,
		},
		&container.HostConfig{
			Mounts: []mount.Mount{{
				Type:   mount.TypeVolume,
				Source: volumeName(id),
				Target: appDir,
			}},
		},
		nil, nil, installerName,
	)
	if err != nil {
		return err
	}
	// Installer временный — всегда убираем за собой.
	defer func() {
		_ = m.cli.ContainerRemove(context.WithoutCancel(ctx), installerName,
			container.RemoveOptions{Force: true})
	}()

	// Копируем код в /app (пишется в смонтированный volume).
	if err := m.cli.CopyToContainer(ctx, resp.ID, appDir,
		bytes.NewReader(codeTar), container.CopyToContainerOptions{}); err != nil {
		return err
	}

	if !hasRequirements {
		return nil
	}

	// Ставим зависимости и ждём завершения.
	if err := m.cli.ContainerStart(ctx, resp.ID, container.StartOptions{}); err != nil {
		return err
	}
	statusCh, errCh := m.cli.ContainerWait(ctx, resp.ID, container.WaitConditionNotRunning)
	select {
	case err := <-errCh:
		if err != nil {
			return err
		}
	case status := <-statusCh:
		if status.StatusCode != 0 {
			return fmt.Errorf("%w: pip exit %d", ErrInstallFailed, status.StatusCode)
		}
	}
	return nil
}

func (m *Manager) createBotContainer(ctx context.Context, id string, spec Spec, createdAt string) error {
	labels := map[string]string{
		labelManaged:    "true",
		labelID:         id,
		labelName:       spec.Name,
		labelEntrypoint: spec.Entrypoint,
		labelMemoryMB:   strconv.Itoa(spec.Limits.MemoryMB),
		labelCPUs:       strconv.FormatFloat(spec.Limits.CPUs, 'g', -1, 64),
		labelCreatedAt:  createdAt,
	}

	_, err := m.cli.ContainerCreate(ctx,
		&container.Config{
			Image:      BaseImage,
			Cmd:        strslice.StrSlice{"python", spec.Entrypoint},
			Env:        []string{"PYTHONPATH=" + depsDir},
			WorkingDir: appDir,
			Labels:     labels,
		},
		&container.HostConfig{
			RestartPolicy: container.RestartPolicy{Name: container.RestartPolicyUnlessStopped},
			Resources: container.Resources{
				Memory:   int64(spec.Limits.MemoryMB) * 1024 * 1024,
				NanoCPUs: int64(spec.Limits.CPUs * 1e9),
			},
			Mounts: []mount.Mount{{
				Type:   mount.TypeVolume,
				Source: volumeName(id),
				Target: appDir,
			}},
		},
		nil, nil, containerName(id),
	)
	return err
}

func containerName(id string) string { return containerPrefix + id }
func volumeName(id string) string    { return containerPrefix + id }

// fromSummary строит Bot из метаданных контейнера.
func fromSummary(s container.Summary) Bot {
	l := s.Labels
	mem, _ := strconv.Atoi(l[labelMemoryMB])
	cpus, _ := strconv.ParseFloat(l[labelCPUs], 64)
	return Bot{
		ID:         l[labelID],
		Name:       l[labelName],
		Entrypoint: l[labelEntrypoint],
		Status:     s.State,
		Limits:     Limits{MemoryMB: mem, CPUs: cpus},
		Image:      BaseImage,
		CreatedAt:  l[labelCreatedAt],
	}
}

// normalizeSpec валидирует спек и подставляет дефолтные лимиты.
func normalizeSpec(spec Spec) (Spec, error) {
	spec.Name = strings.TrimSpace(spec.Name)
	spec.Entrypoint = strings.TrimSpace(spec.Entrypoint)
	if spec.Name == "" || spec.Entrypoint == "" {
		return spec, ErrInvalidSpec
	}
	if spec.Limits.MemoryMB <= 0 {
		spec.Limits.MemoryMB = defaultMemoryMB
	}
	if spec.Limits.CPUs <= 0 {
		spec.Limits.CPUs = defaultCPUs
	}
	return spec, nil
}

// prepareCode распаковывает gzip, проверяет наличие entrypoint и возвращает
// плоский tar для CopyToContainer, а также признак наличия requirements.txt.
func prepareCode(codeTarGz []byte, entrypoint string) (codeTar []byte, hasRequirements bool, err error) {
	gz, err := gzip.NewReader(bytes.NewReader(codeTarGz))
	if err != nil {
		return nil, false, ErrInvalidArchive
	}
	defer gz.Close()

	var out bytes.Buffer
	tw := tar.NewWriter(&out)
	tr := tar.NewReader(gz)

	entryFound := false
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, false, ErrInvalidArchive
		}
		// Нормализуем имена: без ведущих "./" и "/".
		name := strings.TrimPrefix(hdr.Name, "./")
		name = strings.TrimPrefix(name, "/")
		if name == "" {
			continue
		}
		hdr.Name = name

		base := path.Base(name)
		if name == entrypoint || base == entrypoint {
			entryFound = true
		}
		if name == "requirements.txt" || base == "requirements.txt" {
			hasRequirements = true
		}

		if err := tw.WriteHeader(hdr); err != nil {
			return nil, false, err
		}
		if _, err := io.Copy(tw, tr); err != nil {
			return nil, false, err
		}
	}
	if err := tw.Close(); err != nil {
		return nil, false, err
	}
	if !entryFound {
		return nil, false, ErrEntrypointNotFound
	}
	return out.Bytes(), hasRequirements, nil
}

func newID() (string, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
