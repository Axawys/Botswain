package bots

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"testing"
)

// makeTarGz собирает .tar.gz из карты «имя файла → содержимое».
func makeTarGz(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, content := range files {
		hdr := &tar.Header{Name: name, Mode: 0o644, Size: int64(len(content))}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestPrepareCode(t *testing.T) {
	t.Run("находит entrypoint и requirements", func(t *testing.T) {
		archive := makeTarGz(t, map[string]string{
			"main.py":          "print('hi')",
			"requirements.txt": "requests",
		})
		tarBytes, hasReq, err := prepareCode(archive, "main.py")
		if err != nil {
			t.Fatalf("неожиданная ошибка: %v", err)
		}
		if !hasReq {
			t.Error("ожидался признак наличия requirements.txt")
		}
		if len(tarBytes) == 0 {
			t.Error("пустой выходной tar")
		}
	})

	t.Run("без requirements", func(t *testing.T) {
		archive := makeTarGz(t, map[string]string{"main.py": "x"})
		_, hasReq, err := prepareCode(archive, "main.py")
		if err != nil {
			t.Fatal(err)
		}
		if hasReq {
			t.Error("requirements.txt не должно быть обнаружено")
		}
	})

	t.Run("нет entrypoint → ошибка", func(t *testing.T) {
		archive := makeTarGz(t, map[string]string{"other.py": "x"})
		_, _, err := prepareCode(archive, "main.py")
		if !errors.Is(err, ErrEntrypointNotFound) {
			t.Fatalf("ожидалась ErrEntrypointNotFound, получено: %v", err)
		}
	})

	t.Run("битый архив → ошибка", func(t *testing.T) {
		_, _, err := prepareCode([]byte("not a gzip"), "main.py")
		if !errors.Is(err, ErrInvalidArchive) {
			t.Fatalf("ожидалась ErrInvalidArchive, получено: %v", err)
		}
	})
}

func TestNormalizeSpec(t *testing.T) {
	t.Run("подставляет дефолтные лимиты", func(t *testing.T) {
		got, err := normalizeSpec(Spec{Name: "bot", Entrypoint: "main.py"})
		if err != nil {
			t.Fatal(err)
		}
		if got.Limits.MemoryMB != defaultMemoryMB || got.Limits.CPUs != defaultCPUs {
			t.Errorf("лимиты по умолчанию не подставлены: %+v", got.Limits)
		}
	})

	t.Run("пустое имя → ErrInvalidSpec", func(t *testing.T) {
		_, err := normalizeSpec(Spec{Entrypoint: "main.py"})
		if !errors.Is(err, ErrInvalidSpec) {
			t.Fatalf("ожидалась ErrInvalidSpec, получено: %v", err)
		}
	})
}
