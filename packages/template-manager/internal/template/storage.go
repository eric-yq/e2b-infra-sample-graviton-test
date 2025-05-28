package template

import (
	"context"
	"fmt"

	"github.com/e2b-dev/infra/packages/shared/pkg/storage"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage/s3"
)

type Storage struct {
	bucket *s3.BucketHandle
}

func NewStorage(ctx context.Context) *Storage {
	return &Storage{
		bucket: s3.GetTemplateBucket(),
	}
}

func (t *Storage) Remove(ctx context.Context, buildId string) error {
	err := s3.RemoveDir(ctx, t.bucket, buildId)
	if err != nil {
		return fmt.Errorf("error when removing template '%s': %w", buildId, err)
	}

	return nil
}

func (t *Storage) NewBuild(files *storage.TemplateFiles) *storage.TemplateBuild {
	return storage.NewTemplateBuild(nil, nil, files)
}
