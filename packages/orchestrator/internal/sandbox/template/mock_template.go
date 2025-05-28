package template

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/e2b-dev/infra/packages/orchestrator/internal/sandbox/build"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage/header"
)

// mockTemplate is a template implementation that doesn't require actual storage access.
// It's used in the mock-sandbox environment for testing.
type mockTemplate struct {
	files *storage.TemplateCacheFiles
}

// newMockTemplate creates a new mock template.
func newMockTemplate(
	templateId,
	buildId,
	kernelVersion,
	firecrackerVersion string,
	hugePages bool,
) Template {
	files, _ := storage.NewTemplateFiles(
		templateId,
		buildId,
		kernelVersion,
		firecrackerVersion,
		hugePages,
	).NewTemplateCacheFiles()

	// Create the cache directory if it doesn't exist
	os.MkdirAll(files.CacheDir(), os.ModePerm)

	return &mockTemplate{
		files: files,
	}
}

// Files returns the template cache files.
func (t *mockTemplate) Files() *storage.TemplateCacheFiles {
	return t.files
}

// Memfile returns a mock storage that doesn't actually read from disk.
func (t *mockTemplate) Memfile() (*Storage, error) {
	// Create a mock header
	metadata := &header.Metadata{
		Version:    1,
		BlockSize:  4096,
		Size:       1024 * 1024, // 1MB
		Generation: 1,
	}
	h := header.NewHeader(metadata, nil)

	// Create a mock file
	return &Storage{
		header: h,
		source: build.NewFile(h, nil, build.Memfile),
	}, nil
}

// Rootfs returns a mock storage that doesn't actually read from disk.
func (t *mockTemplate) Rootfs() (*Storage, error) {
	// Create a mock header
	metadata := &header.Metadata{
		Version:    1,
		BlockSize:  4096,
		Size:       10 * 1024 * 1024, // 10MB
		Generation: 1,
	}
	h := header.NewHeader(metadata, nil)

	// Create a mock file
	return &Storage{
		header: h,
		source: build.NewFile(h, nil, build.Rootfs),
	}, nil
}

// Snapfile returns a mock file that doesn't actually exist on disk.
func (t *mockTemplate) Snapfile() (File, error) {
	// Create a mock file path
	path := filepath.Join(t.files.CacheDir(), "mock-snapfile")

	// Create an empty file
	f, err := os.Create(path)
	if err != nil {
		return nil, fmt.Errorf("failed to create mock snapfile: %w", err)
	}
	f.Close()

	return &LocalFile{
		path: path,
	}, nil
}

// Close cleans up any resources used by the mock template.
func (t *mockTemplate) Close() error {
	// Nothing to clean up
	return nil
}
