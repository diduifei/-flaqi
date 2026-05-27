package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go-backend/internal/app"
	"go-backend/internal/config"
)

func main() {
	cfg := config.FromEnv()
	if cfg.JWTSecret == "" {
		secret, err := generateJWTSecret()
		if err != nil {
			log.Fatalf("JWT_SECRET is empty and random secret generation failed: %v", err)
		}
		cfg.JWTSecret = secret
		log.Println("warning: JWT_SECRET is empty; generated an ephemeral secret for this process")
	}
	log.Printf("starting go-backend on %s (db=%s)", cfg.Addr, cfg.DBPath)

	a, err := app.New(cfg)
	if err != nil {
		log.Fatalf("failed to create app: %v", err)
	}

	errCh := make(chan error, 1)
	go func() {
		errCh <- a.Run()
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("received signal %s, shutting down", sig)
	case runErr := <-errCh:
		if runErr != nil && !errors.Is(runErr, http.ErrServerClosed) {
			log.Fatalf("server stopped unexpectedly: %v", runErr)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := a.Shutdown(ctx); err != nil {
		log.Fatalf("shutdown failed: %v", err)
	}
}

func generateJWTSecret() (string, error) {
	var buf [32]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf[:]), nil
}
