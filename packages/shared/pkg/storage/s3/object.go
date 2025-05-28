package s3

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// 存储操作相关常量
const (
	// 读取操作超时
	readTimeout = 10 * time.Second
	// 一般操作超时
	operationTimeout = 5 * time.Second
	// 缓冲区大小
	bufferSize = 2 << 21
	// 初始重试等待时间
	initialBackoff = 10 * time.Millisecond
	// 最大重试等待时间
	maxBackoff = 10 * time.Second
	// 重试等待时间倍数
	backoffMultiplier = 2
	// 最大重试次数
	maxAttempts = 10
)

// 存储操作接口定义
type StorageOperations interface {
	WriteTo(dst io.Writer) (int64, error)
	ReadFrom(src io.Reader) (int64, error)
	ReadAt(b []byte, off int64) (n int, err error)
	Size() (int64, error)
	Delete() error
}

// Object 表示S3存储桶中的一个对象
type Object struct {
	bucket *BucketHandle
	key    string
	ctx    context.Context
}

// 确保Object实现了StorageOperations接口
var _ StorageOperations = (*Object)(nil)

// 对象管理相关函数

// NewObject 创建一个新的S3对象引用
func NewObject(ctx context.Context, bucket *BucketHandle, objectPath string) *Object {
	return &Object{
		bucket: bucket,
		key:    objectPath,
		ctx:    ctx,
	}
}

// Delete 删除S3对象
func (o *Object) Delete() error {
	ctx, cancel := context.WithTimeout(o.ctx, operationTimeout)
	defer cancel()

	_, err := o.bucket.Client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(o.bucket.Name),
		Key:    aws.String(o.key),
	})

	if err != nil {
		return fmt.Errorf("删除S3对象失败: %w", err)
	}

	return nil
}

// Size 获取S3对象的大小
func (o *Object) Size() (int64, error) {
	ctx, cancel := context.WithTimeout(o.ctx, operationTimeout)
	defer cancel()

	resp, err := o.bucket.Client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(o.bucket.Name),
		Key:    aws.String(o.key),
	})

	if err != nil {
		return 0, fmt.Errorf("获取S3对象(%s)属性失败: %w", o.key, err)
	}

	return *resp.ContentLength, nil
}

// 数据读写相关函数

// WriteTo 将S3对象内容写入目标写入器
func (o *Object) WriteTo(dst io.Writer) (int64, error) {
	ctx, cancel := context.WithTimeout(o.ctx, readTimeout)
	defer cancel()

	resp, err := o.bucket.Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(o.bucket.Name),
		Key:    aws.String(o.key),
	})
	if err != nil {
		return 0, fmt.Errorf("下载S3对象失败: %w", err)
	}
	defer resp.Body.Close()

	return io.Copy(dst, resp.Body)
}

// ReadFrom 从源读取器读取内容并上传到S3对象
func (o *Object) ReadFrom(src io.Reader) (int64, error) {
	uploader := manager.NewUploader(o.bucket.Client)

	_, err := uploader.Upload(o.ctx, &s3.PutObjectInput{
		Bucket: aws.String(o.bucket.Name),
		Key:    aws.String(o.key),
		Body:   src,
	})

	if err != nil {
		return 0, fmt.Errorf("上传到S3失败: %w", err)
	}

	// S3 API不返回写入的字节数，所以这里返回0
	return 0, nil
}

// ReadAt 从S3对象的指定偏移量读取数据
func (o *Object) ReadAt(b []byte, off int64) (n int, err error) {
	ctx, cancel := context.WithTimeout(o.ctx, readTimeout)
	defer cancel()

	resp, err := o.bucket.Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(o.bucket.Name),
		Key:    aws.String(o.key),
		Range:  aws.String(fmt.Sprintf("bytes=%d-%d", off, off+int64(len(b))-1)),
	})

	if err != nil {
		return 0, fmt.Errorf("创建S3读取器失败: %w", err)
	}

	defer resp.Body.Close()

	return readAllFromResponse(resp.Body, b)
}

// 辅助函数

// readAllFromResponse 从响应体读取数据到缓冲区
func readAllFromResponse(body io.ReadCloser, buffer []byte) (int, error) {
	var totalRead int

	for {
		nr, readErr := body.Read(buffer[totalRead:])
		totalRead += nr

		if readErr == nil {
			continue
		}

		if errors.Is(readErr, io.EOF) {
			break
		}

		return totalRead, fmt.Errorf("从响应体读取失败: %w", readErr)
	}

	return totalRead, nil
}

// 文件上传相关函数

// UploadWithCli 使用AWS CLI上传文件到S3
func (o *Object) UploadWithCli(ctx context.Context, path string) error {
	cmd := exec.CommandContext(
		ctx,
		"aws",
		"s3",
		"cp",
		path,
		fmt.Sprintf("s3://%s/%s", o.bucket.Name, o.key),
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("使用CLI上传文件到S3失败: %w\n%s", err, string(output))
	}

	return nil
}

// Upload 上传本地文件到S3对象
func (o *Object) Upload(ctx context.Context, path string) error {
	return o.uploadFileWithMultipart(ctx, path)
}

// uploadFileWithMultipart 使用分块上传方式上传文件
func (o *Object) uploadFileWithMultipart(ctx context.Context, path string) error {
	// 打开本地文件
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("打开文件失败: %w", err)
	}
	defer file.Close()

	// 创建上传管理器并配置分块大小
	uploader := manager.NewUploader(o.bucket.Client, func(u *manager.Uploader) {
		u.PartSize = 100 * 1024 * 1024 // 100MB per part
	})

	// 执行上传
	_, err = uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket: aws.String(o.bucket.Name),
		Key:    aws.String(o.key),
		Body:   file,
	})
	if err != nil {
		return fmt.Errorf("上传失败: %w", err)
	}

	return nil
}
