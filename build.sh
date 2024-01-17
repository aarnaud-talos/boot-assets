#/bin/bash

git submodule update --init

docker buildx use local || docker buildx create --name local --use --config=buildkit.config

cd pkgs
export PKGS_VERSION=$(git describe --tag --always --dirty)
make PLATFORM=linux/amd64 USERNAME=aarnaud-talos PUSH=true

cd extensions
export EXTENSION_VERSION=$(git describe --tag --always --dirty)
make PLATFORM=linux/amd64 PKGS=${PKGS_VERSION} USERNAME=aarnaud-talos PUSH=true

cd talos
export TALOS_VERSION=$(git describe --tag --always --dirty)
make installer PLATFORM=linux/amd64 USERNAME=aarnaud-talos PKGS=${PKGS_VERSION} PKG_KERNEL=ghcr.io/aarnaud-talos/kernel:${PKGS_VERSION} PUSH=true
make imager PLATFORM=linux/amd64 INSTALLER_ARCH=amd64 USERNAME=aarnaud-talos PKGS=${PKGS_VERSION} PKG_KERNEL=ghcr.io/aarnaud-talos/kernel:${PKGS_VERSION} PUSH=true

docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal --output-kind installer \
  --output-image-options raw \
  --system-extension-image ghcr.io/siderolabs/intel-ucode:20231114 \
  --system-extension-image ghcr.io/siderolabs/i915-ucode:20231111 \
  --system-extension-image ghcr.io/aarnaud-talos/applesmc-t2:${EXTENSION_VERSION}
xz -d installer-amd64.tar.xz

crane push --platform linux/amd64 _out/installer-amd64.tar ghcr.io/aarnaud-talos/installer:${TALOS_VERSION}-applesmc-t2