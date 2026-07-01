// Package version хранит информацию о сборке агента.
// Значения переопределяются на этапе линковки через -ldflags.
package version

// Значения по умолчанию используются при сборке без ldflags (например, go run).
var (
	// Version — семантическая версия агента.
	Version = "0.1.0-dev"
	// Commit — короткий git-хэш сборки.
	Commit = "unknown"
)
