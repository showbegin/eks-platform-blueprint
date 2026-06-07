// sample-producer
//
// Receives HTTP POST /messages, enqueues to SQS, returns 202 with messageId.
// Demonstrates: IRSA scoped to SQS:SendMessage only.

package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	messagesEnqueued = promauto.NewCounter(prometheus.CounterOpts{
		Name: "sample_producer_messages_enqueued_total",
		Help: "Total messages successfully enqueued to SQS",
	})
	enqueueFailures = promauto.NewCounter(prometheus.CounterOpts{
		Name: "sample_producer_enqueue_failures_total",
		Help: "Total enqueue failures",
	})
)

type Message struct {
	Text     string            `json:"text"`
	Metadata map[string]string `json:"metadata,omitempty"`
}

type Response struct {
	MessageID string `json:"messageId"`
	Queue     string `json:"queue"`
}

type producer struct {
	client   *sqs.Client
	queueURL string
	logger   *slog.Logger
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	queueURL := os.Getenv("SQS_QUEUE_URL")
	if queueURL == "" {
		logger.Error("SQS_QUEUE_URL is required")
		os.Exit(1)
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		logger.Error("failed to load AWS config", "error", err)
		os.Exit(1)
	}

	p := &producer{
		client:   sqs.NewFromConfig(cfg),
		queueURL: queueURL,
		logger:   logger,
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", p.handleRoot)
	mux.HandleFunc("/healthz", p.handleHealth)
	mux.HandleFunc("/messages", p.handleMessages)
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	logger.Info("sample-producer listening", "port", port, "queue", queueURL)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("server failed", "error", err)
		os.Exit(1)
	}
}

func (p *producer) handleRoot(w http.ResponseWriter, _ *http.Request) {
	resp := map[string]string{
		"service":     "sample-producer",
		"environment": os.Getenv("ENVIRONMENT"),
		"version":     version(),
	}
	writeJSON(w, http.StatusOK, resp)
}

func (p *producer) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func (p *producer) handleMessages(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var msg Message
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if msg.Text == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "text is required"})
		return
	}

	body, err := json.Marshal(msg)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to marshal"})
		return
	}

	out, err := p.client.SendMessage(r.Context(), &sqs.SendMessageInput{
		QueueUrl:    &p.queueURL,
		MessageBody: ptr(string(body)),
	})
	if err != nil {
		enqueueFailures.Inc()
		p.logger.Error("send message failed", "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "failed to enqueue"})
		return
	}

	messagesEnqueued.Inc()
	p.logger.Info("message enqueued", "messageId", *out.MessageId)
	writeJSON(w, http.StatusAccepted, Response{
		MessageID: *out.MessageId,
		Queue:     p.queueURL,
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func version() string {
	if v := os.Getenv("VERSION"); v != "" {
		return v
	}
	return "dev"
}

func ptr[T any](v T) *T { return &v }
