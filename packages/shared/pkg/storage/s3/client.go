package s3

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// 客户端配置常量
const (
	// 客户端连接超时时间
	clientConnectTimeout = 30 * time.Second
	// 最大重试次数
	maxRetryAttempts = 3
)

// createS3Client 创建并配置一个新的S3客户端
// 该函数加载AWS默认配置并创建S3服务客户端
func newClient(ctx context.Context) (*s3.Client, error) {
	// 创建带超时的上下文
	ctxWithTimeout, cancel := context.WithTimeout(ctx, clientConnectTimeout)
	defer cancel()

	// 加载AWS配置
	configOptions := []func(*config.LoadOptions) error{
		config.WithRetryMaxAttempts(maxRetryAttempts),
	}

	cfg, err := config.LoadDefaultConfig(ctxWithTimeout, configOptions...)
	if err != nil {
		return nil, fmt.Errorf("无法加载AWS配置: %w", err)
	}

	// 创建并返回S3客户端
	return s3.NewFromConfig(cfg), nil
}
