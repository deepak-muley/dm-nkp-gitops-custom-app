#!/bin/bash
set -euo pipefail

# Build script for dm-nkp-gitops-custom-app

APP_NAME="dm-nkp-gitops-custom-app"
BUILD_DIR="bin"
VERSION="${VERSION:-0.1.0}"

echo "Building ${APP_NAME} version ${VERSION}..."

# Create build directory
mkdir -p ${BUILD_DIR}

# Build for current platform
go build -o ${BUILD_DIR}/${APP_NAME} -v ./cmd/app

echo "Build complete: ${BUILD_DIR}/${APP_NAME}"

# Show binary info
if [ -f "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "Binary size: $(du -h ${BUILD_DIR}/${APP_NAME} | cut -f1)"
    file ${BUILD_DIR}/${APP_NAME}
fi
