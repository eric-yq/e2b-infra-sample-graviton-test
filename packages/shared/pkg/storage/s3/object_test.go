package s3

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 测试环境配置
type testConfig struct {
	bucketName string
	region     string
	filePath   string
	timeout    time.Duration
}

// 从环境变量获取测试配置
func getTestConfig() testConfig {
	return testConfig{
		bucketName: os.Getenv("TEMPLATE_BUCKET_NAME"),
		region:     getEnvWithDefault("AWS_REGION", "us-east-1"),
		filePath:   getEnvWithDefault("LARGE_FILE_PATH", "object.go"),
		timeout:    30 * time.Second,
	}
}

// 获取环境变量，如果不存在则使用默认值
func getEnvWithDefault(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// 创建测试用的S3客户端
func createTestS3Client(t *testing.T, region string) *s3.Client {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(region))
	require.NoError(t, err, "加载AWS配置应该成功")

	return s3.NewFromConfig(cfg)
}

// TestObject_WithRealS3Client 使用真实S3客户端测试对象操作
func TestObject_WithRealS3Client(t *testing.T) {
	// 获取测试配置
	cfg := getTestConfig()

	// 检查必要的环境变量
	if cfg.bucketName == "" {
		t.Fatal("未设置TEMPLATE_BUCKET_NAME环境变量")
		return
	}

	// 记录测试配置
	t.Logf("测试配置: 存储桶=%s, 区域=%s, 文件=%s",
		cfg.bucketName, cfg.region, cfg.filePath)

	// 创建测试上下文
	ctx, cancel := context.WithTimeout(context.Background(), cfg.timeout)
	defer cancel()

	// 创建S3客户端
	client := createTestS3Client(t, cfg.region)

	// 创建存储桶处理器
	bucket := &BucketHandle{
		Name:   cfg.bucketName,
		Client: client,
	}

	// 运行测试用例
	t.Run("上传和删除对象", func(t *testing.T) {
		testUploadAndDelete(t, ctx, bucket, cfg.filePath)
	})
}

// 测试上传和删除功能
func testUploadAndDelete(t *testing.T, ctx context.Context, bucket *BucketHandle, filePath string) {
	// 创建测试对象
	obj := NewObject(ctx, bucket, filePath)

	// 测试上传功能
	err := obj.Upload(ctx, filePath)
	assert.NoError(t, err, "上传对象应该成功")
	t.Logf("成功上传对象 %s", filePath)

	// 验证对象存在并获取大小
	size, err := obj.Size()
	assert.NoError(t, err, "获取对象大小应该成功")
	t.Logf("对象大小: %d 字节", size)

	// 测试删除功能
	err = obj.Delete()
	assert.NoError(t, err, "删除对象应该成功")
	t.Logf("成功删除对象 %s", filePath)

	// 验证对象已被删除
	_, err = obj.Size()
	assert.Error(t, err, "对象应该已被删除")
	t.Logf("确认对象已被删除")
}
