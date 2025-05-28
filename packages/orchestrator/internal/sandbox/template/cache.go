package template

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/jellydator/ttlcache/v3"

	"github.com/e2b-dev/infra/packages/orchestrator/internal/sandbox/build"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage/header"
	"github.com/e2b-dev/infra/packages/shared/pkg/storage/s3"
)

// How long to keep the template in the cache since the last access.
// Should be longer than the maximum possible sandbox lifetime.
const templateExpiration = time.Hour * 25

type Cache struct {
	cache      *ttlcache.Cache[string, Template]
	bucket     *s3.BucketHandle
	ctx        context.Context
	buildStore *build.DiffStore
}

func NewCache(ctx context.Context) (*Cache, error) {
	cache := ttlcache.New(
		ttlcache.WithTTL[string, Template](templateExpiration),
	)

	cache.OnEviction(func(ctx context.Context, reason ttlcache.EvictionReason, item *ttlcache.Item[string, Template]) {
		template := item.Value()

		err := template.Close()
		if err != nil {
			fmt.Printf("[template data cache]: failed to cleanup template data for item %s: %v\n", item.Key(), err)
		}
	})

	go cache.Start()

	// Get the S3 bucket for templates
	bucket := s3.GetTemplateBucket()

	// Create the build store
	buildStore, err := build.NewDiffStore(bucket, ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create build store: %w", err)
	}

	return &Cache{
		bucket:     bucket,
		buildStore: buildStore,
		cache:      cache,
		ctx:        ctx,
	}, nil
}

func (c *Cache) Items() map[string]*ttlcache.Item[string, Template] {
	return c.cache.Items()
}

// GetTemplate gets a template from the cache or creates a new one.
// In mock mode, it will return a mock template if the template doesn't exist in the cache.
func (c *Cache) GetTemplate(
	templateId,
	buildId,
	kernelVersion,
	firecrackerVersion string,
	hugePages bool,
	isSnapshot bool,
) (Template, error) {
	// Check if we're in mock mode
	if os.Getenv("MOCK_SANDBOX") == "true" {
		// Try to get the template from the cache first
		cacheKey := fmt.Sprintf("%s-%s-%s-%s-%v-%v", templateId, buildId, kernelVersion, firecrackerVersion, hugePages, isSnapshot)
		if item := c.cache.Get(cacheKey); item != nil {
			return item.Value(), nil
		}

		// If not in cache, create a mock template
		mockTemplate := newMockTemplate(templateId, buildId, kernelVersion, firecrackerVersion, hugePages)

		// Add it to the cache
		item := c.cache.Set(cacheKey, mockTemplate, templateExpiration)

		return item.Value(), nil
	}

	// Normal flow for non-mock mode
	storageTemplate, err := newTemplateFromStorage(
		templateId,
		buildId,
		kernelVersion,
		firecrackerVersion,
		hugePages,
		isSnapshot,
		nil,
		nil,
		c.bucket,
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create template cache from storage: %w", err)
	}

	t, found := c.cache.GetOrSet(
		storageTemplate.Files().CacheKey(),
		storageTemplate,
		ttlcache.WithTTL[string, Template](templateExpiration),
	)

	if !found {
		go storageTemplate.Fetch(c.ctx, c.buildStore)
	}

	return t.Value(), nil
}

func (c *Cache) AddSnapshot(
	templateId,
	buildId,
	kernelVersion,
	firecrackerVersion string,
	hugePages bool,
	memfileHeader *header.Header,
	rootfsHeader *header.Header,
	localSnapfile *LocalFile,
	memfileDiff build.Diff,
	rootfsDiff build.Diff,
) error {
	// Check if we're in mock mode
	if os.Getenv("MOCK_SANDBOX") == "true" {
		// In mock mode, we don't need to do anything
		return nil
	}

	switch memfileDiff.(type) {
	case *build.NoDiff:
		break
	default:
		c.buildStore.Add(buildId, build.Memfile, memfileDiff)
	}

	switch rootfsDiff.(type) {
	case *build.NoDiff:
		break
	default:
		c.buildStore.Add(buildId, build.Rootfs, rootfsDiff)
	}

	storageTemplate, err := newTemplateFromStorage(
		templateId,
		buildId,
		kernelVersion,
		firecrackerVersion,
		hugePages,
		true,
		memfileHeader,
		rootfsHeader,
		c.bucket,
		localSnapfile,
	)
	if err != nil {
		return fmt.Errorf("failed to create template cache from storage: %w", err)
	}

	_, found := c.cache.GetOrSet(
		storageTemplate.Files().CacheKey(),
		storageTemplate,
		ttlcache.WithTTL[string, Template](templateExpiration),
	)

	if !found {
		go storageTemplate.Fetch(c.ctx, c.buildStore)
	}

	return nil
}
