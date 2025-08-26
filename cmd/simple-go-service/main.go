package main

import (
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/gin-gonic/gin"
	internal "github.com/nenov92/simple-go-service/cmd/simple-go-service/internal"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
)

func main() {
	logrus.SetOutput(os.Stdout)
	logrus.Info("starting application...")

	gin.SetMode(gin.ReleaseMode)
	handler := gin.New()

	presenter := internal.NewPresenter()
	handler.GET("/v1/data", presenter.GetData)

	logrus.Info("preparing httpServer...")
	httpServer := &http.Server{
		Addr:    fmt.Sprintf("0.0.0.0:8080"),
		Handler: handler,
	}
	go func() {
		logrus.Info("starting httpServer...")
		if err := httpServer.ListenAndServe(); err != http.ErrServerClosed {
			logrus.Error(errors.Wrap(err, "server returned an error"))
		}
	}()

	waitExitSignal()
}

func waitExitSignal() {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan,
		syscall.SIGINT,
		syscall.SIGTERM,
		syscall.SIGQUIT)
	<-sigChan
	signal.Stop(sigChan)
}
