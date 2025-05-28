package s3

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// RemoveDir deletes all objects under the specified directory prefix in the bucket
func RemoveDir(ctx context.Context, bucket *BucketHandle, dirPath string) error {
	// Create a paginator to list all objects with the directory prefix
	objectLister := s3.NewListObjectsV2Paginator(bucket.Client, &s3.ListObjectsV2Input{
		Bucket: aws.String(bucket.Name),
		Prefix: aws.String(dirPath + "/"),
	})

	// Process each page of results
	for objectLister.HasMorePages() {
		// Get the next page of objects
		resultPage, err := objectLister.NextPage(ctx)
		if err != nil {
			return fmt.Errorf("failed to list objects in directory '%s': %w", dirPath, err)
		}

		// If no objects found, we're done
		if len(resultPage.Contents) == 0 {
			break
		}

		// Prepare object identifiers for batch deletion
		objectsToDelete := make([]types.ObjectIdentifier, len(resultPage.Contents))
		for i, objectInfo := range resultPage.Contents {
			objectsToDelete[i] = types.ObjectIdentifier{
				Key: objectInfo.Key,
			}
		}

		// Execute batch deletion
		_, err = bucket.Client.DeleteObjects(ctx, &s3.DeleteObjectsInput{
			Bucket: aws.String(bucket.Name),
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		})

		if err != nil {
			return fmt.Errorf("failed to delete objects in directory '%s': %w", dirPath, err)
		}
	}

	return nil
}
