APP := simple-go-service
PKG_PATH := ./cmd/$(APP)
REGISTRY := docker.io/angel3
IMAGE := $(REGISTRY)/$(APP)
TAG := dev-$(shell git rev-parse --short HEAD)

# --- Go helpers ---
tidy:
	go mod tidy

test:
	if command -v ginkgo >/dev/null 2>&1; then \
		ginkgo -r -p -v; \
	else \
		go test ./... -v; \
	fi

build:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o bin/$(APP) $(PKG_PATH)

scan:
	gosec ./... || true
	trivy fs --exit-code 0 --severity HIGH,CRITICAL .

# --- Docker ---
docker-build:
	docker build -t $(IMAGE):$(TAG) .

docker-push: docker-build
	docker push $(IMAGE):$(TAG)

docker-run:
	docker run --rm -p 8080:8080 $(IMAGE):$(TAG)

# --- Kubernetes helpers ---
kctx:
	kubectl config current-context

kns:
	kubectl get ns

# --- clean ---
clean:
	rm -rf bin
