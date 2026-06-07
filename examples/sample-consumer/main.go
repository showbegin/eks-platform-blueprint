// sample-consumer
//
// Polls SQS, writes each message to S3 as processed/<messageId>.json,
// deletes from queue on success. Demonstrates: IRSA scoped to
// SQS:Receive/Delete + S3:PutObject only.

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	messagesProcessed = promauto.NewCounter(prometheus.CounterOpts{
		Name: "sample_consumer_messages_processed_total",
		Help: "Total messages processed and written to S3",
	})
	processFailures = promauto.NewCounter(prometheus.CounterOpts{
		Name: "sample_consumer_process_failures_total",
		Help: "Total processing failures (S3 write or SQS delete)",
	})
	pollErrors = promauto.NewCounter(prometheus.CounterOpts{
		Name: "sample_consumer_poll_errors_total",
		Help: "Total SQS poll errors",
	})
)

type processedMessage struct {
	OriginalMessage json.RawMessage `json:"originalMessage"`
	ProcessedAt     time.Time       `json:"processedAt"`
	Consumer        string          `json:"consumer"`
}

type consumer struct {
	sqs      *sqs.Client
	s3       *s3.Client
	queueURL string
	bucket   string
	logger   *slog.Logger
	healthy  atomic.Bool
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	queueURL := os.Getenv("SQS_QUEUE_URL")
	bucket := os.Getenv("S3_BUCKET")
	if queueURL == "" || bucket == "" {
		logger.Error("SQS_QUEUE_URL and S3_BUCKET are required")
		os.Exit(1)
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		logger.Error("failed to load AWS config", "error", err)
		os.Exit(1)
	}

	c := &consumer{
		sqs:      sqs.NewFromConfig(cfg),
		s3:       s3.NewFromConfig(cfg),
		queueURL: queueURL,
		bucket:   bucket,
		logger:   logger,
	}
	c.healthy.Store(true)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go c.poll(ctx)
	go c.serveHTTP(ctx)

	<-ctx.Done()
	logger.Info("shutting down")
	time.Sleep(2 * time.Second) // grace period for in-flight messages
}

func (c *consumer) poll(ctx context.Context) {
	c.logger.Info("starting SQS poll loop", "queue", c.queueURL)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		out, err := c.sqs.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            &c.queueURL,
			MaxNumberOfMessages: 10,
			WaitTimeSeconds:     20, // long-polling
			VisibilityTimeout:   30,
		})
		if err != nil {
			pollErrors.Inc()
			c.logger.Error("receive failed", "error", err)
			time.Sleep(5 * time.Second)
			continue
		}

		for _, m := range out.Messages {
			if err := c.process(ctx, m); err != nil {
				processFailures.Inc()
				c.logger.Error("process failed", "messageId", aws.ToString(m.MessageId), "error", err)
				continue
			}
			messagesProcessed.Inc()
		}
	}
}

func (c *consumer) process(ctx context.Context, m types.Message) error {
	processed := processedMessage{
		OriginalMessage: json.RawMessage(aws.ToString(m.Body)),
		ProcessedAt:     time.Now().UTC(),
		Consumer:        "sample-consumer",
	}

	body, err := json.Marshal(processed)
	if err != nil {
		return err
	}

	key := "processed/" + aws.ToString(m.MessageId) + ".json"
	if _, err := c.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &c.bucket,
		Key:         &key,
		Body:        bytes.NewReader(body),
		ContentType: aws.String("application/json"),
	}); err != nil {
		return err
	}

	if _, err := c.sqs.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      &c.queueURL,
		ReceiptHandle: m.ReceiptHandle,
	}); err != nil {
		return err
	}

	c.logger.Info("processed message", "messageId", aws.ToString(m.MessageId), "key", key)
	return nil
}

func (c *consumer) serveHTTP(ctx context.Context) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", c.handleRoot)
	mux.HandleFunc("/healthz", c.handleHealth)
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		<-ctx.Done()
		c.healthy.Store(false)
		_ = srv.Shutdown(context.Background())
	}()

	c.logger.Info("sample-consumer HTTP listening", "port", port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		c.logger.Error("http server failed", "error", err)
	}
}

func (c *consumer) handleRoot(w http.ResponseWriter, _ *http.Request) {
	resp := map[string]string{
		"service":     "sample-consumer",
		"environment": os.Getenv("ENVIRONMENT"),
		"version":     version(),
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func (c *consumer) handleHealth(w http.ResponseWriter, _ *http.Request) {
	if !c.healthy.Load() {
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func version() string {
	if v := os.Getenv("VERSION"); v != "" {
		return v
	}
	return "dev"
}
