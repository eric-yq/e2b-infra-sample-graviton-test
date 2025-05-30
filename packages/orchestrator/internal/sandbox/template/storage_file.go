package template

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/e2b-dev/infra/packages/shared/pkg/storage/s3"
)

type storageFile struct {
	path string
}

func newStorageFile(
	ctx context.Context,
	bucket *s3.BucketHandle,
	bucketObjectPath string,
	path string,
) (*storageFile, error) {
	f, err := os.Create(path)
	if err != nil {
		return nil, fmt.Errorf("failed to create file: %w", err)
	}

	defer f.Close()

	object := s3.NewObject(ctx, bucket, bucketObjectPath)

	_, err = object.WriteTo(f)
	if err != nil {
		cleanupErr := os.Remove(path)

		return nil, fmt.Errorf("failed to write to file: %w", errors.Join(err, cleanupErr))
	}

	return &storageFile{
		path: path,
	}, nil
}

func (f *storageFile) Path() string {
	return f.path
}

func (f *storageFile) Close() error {
	return os.Remove(f.path)
}
