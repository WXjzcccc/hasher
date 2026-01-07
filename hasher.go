package main

import (
	"context"
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"hash/crc32"
	"hash/crc64"
	"io"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"sync"

	"github.com/emmansun/gmsm/sm3"
)

type HashResult struct {
	MD5        string
	SHA1       string
	SHA256     string
	SHA512     string
	SM3        string
	CRC32      string
	CRC64_ISO  string
	CRC64_ECMA string
}

type Hasher struct {
	FilePath   string     `json:"filePath"`
	FileName   string     `json:"fileName"`
	FileSize   string     `json:"fileSize"`
	HashResult HashResult `json:"hashResult"`
}

type HashOption struct {
	MD5        bool `json:"MD5"`
	SHA1       bool `json:"SHA1"`
	SHA256     bool `json:"SHA256"`
	SHA512     bool `json:"SHA512"`
	SM3        bool `json:"SM3"`
	CRC32      bool `json:"CRC32"`
	CRC64_ISO  bool `json:"CRC64_ISO"`
	CRC64_ECMA bool `json:"CRC64_ECMA"`
}

var (
	ctx    context.Context
	cancel context.CancelFunc
	mu     sync.Mutex // 保护全局变量
)

func NewHasher() *Hasher {
	return &Hasher{}
}

func NewHasher2(filePath string) Hasher {
	var hasher Hasher
	hasher.FilePath = filePath
	hasher.FileName = filepath.Base(filePath)
	// 检查是否为符号链接
	info, err := os.Lstat(filePath)
	if err != nil {
		log.Printf("获取文件信息时出错: %v\n", err)
		hasher.FileSize = fmt.Sprintf("获取文件信息错误: %v", err)
		hasher.HashResult = HashResult{}
		return hasher
	}
	// 如果是符号链接，跳过
	if info.Mode()&os.ModeSymlink != 0 {
		hasher.FileSize = "符号链接，跳过处理"
		hasher.HashResult = HashResult{}
		return hasher
	}
	hasher.FileSize = getSize(info.Size())
	hasher.HashResult = HashResult{}
	return hasher
}

func walkDir(dirPath string) []string {
	var files []string
	err := filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			log.Printf("访问 %q 时出错: %v\n", path, err)
			return nil // 继续遍历其他文件
		}
		// 跳过根目录自身
		if path == dirPath {
			return nil
		}
		// 检查是否为符号链接
		lstatInfo, err := os.Lstat(path)
		if err != nil {
			log.Printf("检查 %q 是否为符号链接时出错: %v\n", path, err)
			return nil
		}
		// 如果是符号链接，跳过
		if lstatInfo.Mode()&os.ModeSymlink != 0 {
			log.Printf("[符号链接] %s，跳过处理\n", path)
			// 如果是指向目录的符号链接，不要继续遍历
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		// 计算相对于根目录的路径
		if info.IsDir() {
			log.Printf("[文件夹] %s\n", path)
		} else {
			log.Printf("[文件] %s (大小: %d bytes)\n", path, info.Size())
			files = append(files, path)
		}
		return nil
	})

	if err != nil {
		log.Printf("遍历文件夹出错: %v\n", err)
		return nil
	}
	return files
}

func getHashers(filePaths []string) ([]Hasher, error) {
	var hashers []Hasher
	for _, filePath := range filePaths {
		// 使用Lstat而不是Stat，避免跟随符号链接
		fileInfo, err := os.Lstat(filePath)
		if err != nil {
			log.Printf("获取文件信息时出错: %v\n", err)
			continue // 继续处理其他文件
		}
		// 检查是否为符号链接
		if fileInfo.Mode()&os.ModeSymlink != 0 {
			log.Printf("%s 是符号链接，跳过处理\n", filePath)
			continue
		}
		// 如果是目录，遍历目录
		if fileInfo.IsDir() {
			files := walkDir(filePath)
			if files != nil {
				for _, file := range files {
					hashers = append(hashers, NewHasher2(file))
				}
			}
		} else {
			// 如果是普通文件，直接处理
			hashers = append(hashers, NewHasher2(filePath))
		}
	}
	return hashers, nil
}

func getSize(size int64) string {
	const (
		KB = 1 << 10
		MB = 1 << 20
		GB = 1 << 30
		TB = 1 << 40
	)

	switch {
	case size >= TB:
		return fmt.Sprintf("%.2f TB（%d 字节）", float64(size)/TB, size)
	case size >= GB:
		return fmt.Sprintf("%.2f GB（%d 字节）", float64(size)/GB, size)
	case size >= MB:
		return fmt.Sprintf("%.2f MB（%d 字节）", float64(size)/MB, size)
	case size >= KB:
		return fmt.Sprintf("%.2f KB（%d 字节）", float64(size)/KB, size)
	default:
		return fmt.Sprintf("%d 字节", size)
	}
}

// cancelableReader 实现可中断的读取器
type cancelableReader struct {
	ctx    context.Context
	reader io.Reader
}

func newCancelableReader(ctx context.Context, r io.Reader) io.Reader {
	return &cancelableReader{ctx: ctx, reader: r}
}

func (r *cancelableReader) Read(p []byte) (n int, err error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
		return r.reader.Read(p)
	}
}

func CalculateFileHashes(filePath string, hashOption HashOption, ctx context.Context) (*HashResult, error) {
	log.Printf("计算文件：%s", filePath)
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	// 检查是否为符号链接
	lstatInfo, err := os.Lstat(filePath)
	if err != nil {
		return nil, err
	}
	// 如果是符号链接，跳过
	if lstatInfo.Mode()&os.ModeSymlink != 0 {
		log.Printf("%s 是符号链接，跳过处理\n", filePath)
		return nil, nil
	}

	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}

	// 获取文件大小用于优化缓冲区
	fileInfo, err := file.Stat()
	if err != nil {
		return nil, err
	}
	fileSize := fileInfo.Size()
	// 根据文件大小动态调整缓冲区
	bufSize := determineBufferSize(fileSize)
	buf := make([]byte, bufSize)
	log.Printf("Processing %s (size: %d MB) with buffer size: %d KB",
		filePath, fileSize/(1024*1024), bufSize/1024)

	// 初始化所有哈希器
	hashers := make(map[string]hash.Hash)
	if hashOption.MD5 {
		hashers["md5"] = md5.New()
	}
	if hashOption.SHA1 {
		hashers["sha1"] = sha1.New()
	}
	if hashOption.SHA256 {
		hashers["sha256"] = sha256.New()
	}
	if hashOption.SHA512 {
		hashers["sha512"] = sha512.New()
	}
	if hashOption.SM3 {
		hashers["sm3"] = sm3.New()
	}
	if hashOption.CRC32 {
		hashers["crc32"] = crc32.NewIEEE()
	}
	if hashOption.CRC64_ISO {
		hashers["crc64_ISO"] = crc64.New(crc64.MakeTable(crc64.ISO))
	}
	if hashOption.CRC64_ECMA {
		hashers["crc64_ECMA"] = crc64.New(crc64.MakeTable(crc64.ECMA))
	}
	// 创建MultiWriter，可以同时写入所有哈希器
	writers := make([]io.Writer, 0, len(hashers))
	for _, h := range hashers {
		writers = append(writers, h)
	}
	multiWriter := io.MultiWriter(writers...)
	reader := io.Reader(file)
	if ctx != nil {
		reader = newCancelableReader(ctx, file)
	}
	// 使用带缓冲的读取
	//_, err = io.CopyBuffer(multiWriter, file, buf)
	_, err = io.CopyBuffer(multiWriter, reader, buf)
	if err != nil && err != io.EOF {
		return nil, err
	}

	var hashResult HashResult
	if hashOption.MD5 {
		hashResult.MD5 = hex.EncodeToString(hashers["md5"].Sum(nil))
	}
	if hashOption.SHA1 {
		hashResult.SHA1 = hex.EncodeToString(hashers["sha1"].Sum(nil))
	}
	if hashOption.SHA256 {
		hashResult.SHA256 = hex.EncodeToString(hashers["sha256"].Sum(nil))
	}
	if hashOption.SHA512 {
		hashResult.SHA512 = hex.EncodeToString(hashers["sha512"].Sum(nil))
	}
	if hashOption.SM3 {
		hashResult.SM3 = hex.EncodeToString(hashers["sm3"].Sum(nil))
	}
	if hashOption.CRC32 {
		hashResult.CRC32 = hex.EncodeToString(hashers["crc32"].Sum(nil))
	}
	if hashOption.CRC64_ISO {
		hashResult.CRC64_ISO = hex.EncodeToString(hashers["crc64_ISO"].Sum(nil))
	}
	if hashOption.CRC64_ECMA {
		hashResult.CRC64_ECMA = hex.EncodeToString(hashers["crc64_ECMA"].Sum(nil))
	}
	return &hashResult, nil
}

// determineBufferSize 根据文件大小确定最佳缓冲区大小
func determineBufferSize(fileSize int64) int {
	switch {
	case fileSize > 10*1024*1024*1024: // >10GB
		return 16 * 1024 * 1024 // 16MB
	case fileSize > 1024*1024*1024: // >1GB
		return 8 * 1024 * 1024 // 8MB
	case fileSize > 100*1024*1024: // >100MB
		return 2 * 1024 * 1024 // 2MB
	case fileSize > 10*1024*1024: // >10MB
		return 1 * 1024 * 1024 // 1MB
	default:
		return 512 * 1024 // 512KB
	}
}

// FileHashWorker 工作池的工作函数
type FileHashWorker struct {
	hashers     <-chan Hasher
	results     chan<- *FileHashResult
	wg          *sync.WaitGroup
	HashOption2 HashOption
	ctx         context.Context
}

// FileHashResult 包含文件路径和哈希结果
type FileHashResult struct {
	Hashers Hasher
	Result  *HashResult
	Error   error
}

func (w *FileHashWorker) Run() {
	defer w.wg.Done()
	for hasher := range w.hashers {
		select {
		case <-w.ctx.Done():
			return
		default:
			result, err := CalculateFileHashes(hasher.FilePath, w.HashOption2, w.ctx)
			if err != nil {
				if errors.Is(err, context.Canceled) {
					return
				}
			}
			select {
			case w.results <- &FileHashResult{
				Hashers: hasher,
				Result:  result,
				Error:   err,
			}:
			case <-w.ctx.Done():
				return
			}
		}
	}
}

// CalculateMultipleFilesHashesWithLimit 并行计算多个文件的哈希值，限制并发数
func CalculateMultipleFilesHashesWithLimit(hashers []Hasher, maxWorkers int, hashOption HashOption, ctx context.Context) ([]Hasher, error) {
	var results []Hasher
	var mu sync.Mutex

	// 创建带缓冲的channel
	hashersChan := make(chan Hasher, len(hashers))
	resultChan := make(chan *FileHashResult, len(hashers))

	// 启动worker池
	var wg sync.WaitGroup
	for i := 0; i < maxWorkers; i++ {
		wg.Add(1)
		worker := &FileHashWorker{
			hashers:     hashersChan,
			results:     resultChan,
			wg:          &wg,
			HashOption2: hashOption,
			ctx:         ctx,
		}
		go worker.Run()
	}

	// 发送任务
	go func() {
		for _, path := range hashers {
			select {
			case <-ctx.Done():
				close(hashersChan)
				runtime.Goexit()
			default:
				hashersChan <- path
			}
		}
		close(hashersChan)
	}()

	// 等待所有worker完成
	go func() {
		wg.Wait()
		close(resultChan)
	}()

	// 收集结果
	for res := range resultChan {
		if res.Error != nil {
			log.Printf("处理文件 %s 时出错: %v\n", res.Hashers.FilePath, res.Error)
			// 继续处理其他文件，而不是返回错误
			continue
		}
		// 如果结果为nil（可能是符号链接），跳过
		if res.Result != nil {
			mu.Lock()
			res.Hashers.HashResult = *res.Result
			results = append(results, res.Hashers)
			mu.Unlock()
		} else {
			log.Printf("跳过处理符号链接: %s\n", res.Hashers.FilePath)
		}
	}
	return results, nil
}

func CalHash(files []string, hashOptionStr string) []Hasher {
	mu.Lock()
	if cancel != nil {
		cancel() // 取消之前的操作
	}
	ctx, cancel = context.WithCancel(context.Background())
	mu.Unlock()
	defer cancel()
	var hashOption HashOption
	err := json.Unmarshal([]byte(hashOptionStr), &hashOption)
	if err != nil {
		log.Printf("解析哈希选项时出错: %v\n", err)
		return []Hasher{}
	}
	hashers, err := getHashers(files)
	if err != nil {
		log.Printf("获取文件列表时出错: %v\n", err)
		return []Hasher{}
	}
	results, err := CalculateMultipleFilesHashesWithLimit(hashers, 4, hashOption, ctx)
	if err != nil {
		log.Printf("计算哈希值时出错: %v\n", err)
		return []Hasher{}
	}
	return results
}

func StopHash() {
	mu.Lock()
	defer mu.Unlock()
	if cancel != nil {
		cancel()
	}
}
