package template

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"github.com/e2b-dev/infra/packages/orchestrator/internal/sandbox/build"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage/header"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage/s3"
)

type Storage struct {
	header *header.Header
	source *build.File
}

func NewStorage(
	ctx context.Context,
	store *build.DiffStore,
	buildId string,
	fileType build.DiffType,
	blockSize int64,
	isSnapshot bool,
	h *header.Header,
	bucket *s3.BucketHandle,
) (*Storage, error) {
	if isSnapshot && h == nil {
		headerObject := s3.NewObject(ctx, bucket, buildId+"/"+string(fileType)+storage.HeaderSuffix)

		diffHeader, err := header.Deserialize(headerObject)
		if err != nil {
			return nil, fmt.Errorf("failed to deserialize header: %w", err)
		}

		h = diffHeader
	} else if h == nil {
		object := s3.NewObject(ctx, bucket, buildId+"/"+string(fileType))

		size, err := object.Size()
		if err != nil {
			return nil, fmt.Errorf("failed to get object size: %w", err)
		}

		id, err := uuid.Parse(buildId)
		if err != nil {
			return nil, fmt.Errorf("failed to parse build id: %w", err)
		}

		metadata := &header.Metadata{
			Version:     1,
			BlockSize:   uint64(blockSize),
			Size:        uint64(size),
			Generation:  1,
			BuildId:     id,
			BaseBuildId: id,
		}

		h = header.NewHeader(metadata, nil)
	}

	b := build.NewFile(h, store, fileType)

	return &Storage{
		source: b,
		header: h,
	}, nil
}

func (d *Storage) ReadAt(p []byte, off int64) (int, error) {
	return d.source.ReadAt(p, off)
}

func (d *Storage) Size() (int64, error) {
	return int64(d.header.Metadata.Size), nil
}

func (d *Storage) Slice(off, length int64) ([]byte, error) {
	return d.source.Slice(off, length)
}

func (d *Storage) Header() *header.Header {
	return d.header
}
