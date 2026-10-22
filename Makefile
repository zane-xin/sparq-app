SHELL := /bin/sh

GO ?= go
APP_NAME ?= sparq
CMD ?= ./cmd/sparq
BIN_DIR ?= bin
DIST_DIR ?= dist
VERSION ?= dev
override VERSION := $(patsubst v%,%,$(VERSION))
HOST_GOOS := $(shell $(GO) env GOHOSTOS)
HOST_GOARCH := $(shell $(GO) env GOHOSTARCH)
GOOS ?= $(HOST_GOOS)
GOARCH ?= $(HOST_GOARCH)
GOCACHE ?= $(CURDIR)/.cache/go-build
CGO_ENABLED ?= 0
TAGS ?=
RELEASE_TAGS ?= production
LDFLAGS ?=
RELEASE_LDFLAGS ?= $(LDFLAGS)

ifneq ($(VERSION),dev)
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq.version=v$(VERSION)
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq/internal/buildmanifest.HostVersion=v$(VERSION)
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq/internal/buildmanifest.Distribution=official
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq/internal/buildmanifest.HostOwnership=managed
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq/internal/buildmanifest.HostUpdatePolicy=automatic
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq/internal/buildmanifest.AdminOwnership=managed
RELEASE_LDFLAGS += -X github.com/zane-xin/sparq/internal/buildmanifest.AdminUpdatePolicy=automatic
endif

CONFIG ?= config/app.yaml
ENV ?= dev
DEV_ARGS ?= serve --config $(CONFIG) --env $(ENV)
ARGS ?=

PLATFORMS ?= linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64

# 默认目标列表。release 只打包默认壳，不包含 Website 或其他二次开发应用。
.PHONY: help dev run build build-all release release-optimized test fmt tidy clean check-release

# 输出可直接复制执行的常用命令和参数说明。
help:
	@printf '%s\n' \
		'命令:' \
		'  make dev                              以开发配置启动 Sparq' \
		'  make run ARGS="version"               执行任意 Sparq CLI 命令' \
		'  make build                            构建当前平台二进制到 bin/' \
		'  make build GOOS=linux GOARCH=amd64    指定目标平台构建二进制' \
		'  make build-all                        构建 PLATFORMS 中的全部平台' \
		'  make release VERSION=x.y.z ADMIN_ARTIFACT=... ADMIN_SHA256=... ADMIN_VERSION=... 固定 Admin 构建多平台归档' \
		'  make release-optimized VERSION=x.y.z 构建去调试信息的生产归档' \
		'  make test                             执行 go test ./...' \
		'  make fmt                              执行 gofmt' \
		'  make tidy                             执行 go mod tidy' \
		'  make clean                            删除 bin/ 和 dist/'

# 启动本地开发服务，默认读取 config/app.yaml 及其环境覆盖。
dev:
	GOCACHE=$(GOCACHE) GOOS=$(HOST_GOOS) GOARCH=$(HOST_GOARCH) $(GO) run $(CMD) $(DEV_ARGS)

# 执行传入 ARGS 的任意 Sparq CLI 命令，例如 make run ARGS="version"。
run:
	GOCACHE=$(GOCACHE) GOOS=$(HOST_GOOS) GOARCH=$(HOST_GOARCH) $(GO) run $(CMD) $(ARGS)

# 构建当前 GOOS/GOARCH 的开发二进制，保留调试信息便于本地排查。
build:
	@mkdir -p $(BIN_DIR)
	@out="$(BIN_DIR)/$(APP_NAME)"; \
	if [ "$(GOOS)" = "windows" ]; then out="$$out.exe"; fi; \
	printf '==> build %s/%s %s\n' "$(GOOS)" "$(GOARCH)" "$$out"; \
	GOCACHE=$(GOCACHE) CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		$(GO) build -trimpath -tags "$(TAGS)" -ldflags "$(LDFLAGS)" -o "$$out" $(CMD)

# 按 PLATFORMS 交叉构建二进制，不生成发布配置和压缩归档。
build-all:
	@mkdir -p $(DIST_DIR)
	@for platform in $(PLATFORMS); do \
		os="$${platform%/*}"; arch="$${platform#*/}"; \
		name="$(APP_NAME)_$${os}_$${arch}"; \
		out="$(DIST_DIR)/$$name/$(APP_NAME)"; \
		if [ "$$os" = "windows" ]; then out="$$out.exe"; fi; \
		mkdir -p "$(DIST_DIR)/$$name"; \
		printf '==> build %s/%s %s\n' "$$os" "$$arch" "$$out"; \
		GOCACHE=$(GOCACHE) CGO_ENABLED=$(CGO_ENABLED) GOOS=$$os GOARCH=$$arch \
			$(GO) build -trimpath -tags "$(TAGS)" -ldflags "$(LDFLAGS)" -o "$$out" $(CMD) || exit $$?; \
	done

# 发行输入显式固定 Admin 版本与摘要，不读取相邻源码或本地 public/admin。
ADMIN_ARTIFACT ?=
ADMIN_SHA256 ?=
ADMIN_VERSION ?=

release: export GOWORK=off
release: check-release
	@python3 -c 'import re; assert re.fullmatch(r"[0-9]+[.][0-9]+[.][0-9]+(?:-[0-9A-Za-z.-]+)?", "$(VERSION)"), "release 必须提供 VERSION=x.y.z"'
	@python3 scripts/admin-artifact.py --archive "$(ADMIN_ARTIFACT)" --sha256 "$(ADMIN_SHA256)" --version "$(ADMIN_VERSION)"
	@mkdir -p "$(DIST_DIR)"
	@set -eu; for platform in $(PLATFORMS); do \
		os="$${platform%/*}"; arch="$${platform#*/}"; \
		name="$(APP_NAME)_$(VERSION)_$${os}_$${arch}"; \
		dir="$(DIST_DIR)/$$name"; \
		if [ -e "$$dir" ] || [ -e "$$dir.tar.gz" ]; then printf '发布目标已存在：%s\n' "$$dir" >&2; exit 1; fi; \
		mkdir -p "$$dir"; \
		out="$$dir/$(APP_NAME)"; \
		if [ "$$os" = "windows" ]; then out="$$out.exe"; fi; \
		printf '==> release %s/%s %s\n' "$$os" "$$arch" "$$out"; \
		GOCACHE=$(GOCACHE) CGO_ENABLED=$(CGO_ENABLED) GOOS=$$os GOARCH=$$arch \
			$(GO) build -trimpath -tags "$(RELEASE_TAGS)" -ldflags "$(RELEASE_LDFLAGS)" -o "$$out" $(CMD); \
		cp -R config "$$dir/config"; \
		rm -f "$$dir/config/app.install.yaml"; \
		python3 scripts/admin-artifact.py --archive "$(ADMIN_ARTIFACT)" --sha256 "$(ADMIN_SHA256)" --version "$(ADMIN_VERSION)" --output "$$dir/public/admin" > "$$dir/release.json"; \
		( cd "$(DIST_DIR)" && tar -czf "$$name.tar.gz" "$$name" ); \
		python3 -c 'import hashlib,pathlib,sys; p=pathlib.Path(sys.argv[1]); p.with_name(p.name+".sha256").write_text(hashlib.sha256(p.read_bytes()).hexdigest()+"  "+p.name+"\n")' "$$dir.tar.gz"; \
	done

# 构建适合正式分发的精简归档，自动关闭 CGO 并移除符号表、DWARF 和构建 ID。
release-optimized:
	$(MAKE) release VERSION=$(VERSION) PLATFORMS="$(PLATFORMS)" CGO_ENABLED=0 LDFLAGS="$(LDFLAGS) -s -w -buildid="

# 执行默认壳 Go 测试。
test:
	GOCACHE=$(GOCACHE) GOOS=$(HOST_GOOS) GOARCH=$(HOST_GOARCH) $(GO) test ./...

# 格式化当前模块中的 Go 源码。
fmt:
	gofmt -w .

# 整理当前模块的 Go 依赖。
tidy:
	$(GO) mod tidy

# 删除本模块生成的开发和发布产物，不触碰 config、public 和 storage。
clean:
	rm -rf $(BIN_DIR) $(DIST_DIR)

# 发布检查始终关闭外层 workspace。
check-release:
	@python3 scripts/check-release.py check
