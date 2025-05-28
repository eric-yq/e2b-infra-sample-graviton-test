package s3

import (
	"context"
	"sync"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/e2b-dev/infra/packages/shared/pkg/utils"
)

type BucketHandle struct {
	Name   string
	Client *s3.Client
}

var getClient = sync.OnceValue(func() *s3.Client {
	return utils.Must(newClient(context.Background()))
})

func newBucket(bucket string) *BucketHandle {
	return &BucketHandle{
		Name:   bucket,
		Client: getClient(),
	}
}

func getTemplateBucketName() string {
	return utils.RequiredEnv("TEMPLATE_BUCKET_NAME", "bucket for storing template files")
}

func GetTemplateBucket() *BucketHandle {
	return newBucket(getTemplateBucketName())
}
