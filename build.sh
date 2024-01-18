#/bin/bash
set -e

git submodule update --init
git submodule foreach --recursive 'git fetch --tags'

docker buildx use local || docker buildx create --name local --use --config=buildkit.config

cd pkgs
echo "#### using pkgs repository"
export PKGS_VERSION=$(git describe --tag --always --dirty)
make PLATFORM=linux/amd64 USERNAME=aarnaud-talos PUSH=true

cd ../extensions
echo "#### using extensions repository"
export EXTENSION_VERSION=$(git describe --tag --always --dirty)
make PLATFORM=linux/amd64 PKGS=${PKGS_VERSION} USERNAME=aarnaud-talos PKGS_PREFIX=ghcr.io/aarnaud-talos PUSH=true

cd ../talos
echo "#### using talos repository"
export TALOS_VERSION=$(git describe --tag --always --dirty)
make installer PLATFORM=linux/amd64 USERNAME=aarnaud-talos PKGS_PREFIX=ghcr.io/aarnaud-talos PKGS=${PKGS_VERSION} PKG_KERNEL=ghcr.io/aarnaud-talos/kernel:${PKGS_VERSION} PUSH=true
make imager PLATFORM=linux/amd64 INSTALLER_ARCH=amd64 USERNAME=aarnaud-talos PKGS_PREFIX=ghcr.io/aarnaud-talos PKGS=${PKGS_VERSION} PKG_KERNEL=ghcr.io/aarnaud-talos/kernel:${PKGS_VERSION} PUSH=true

docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal --output-kind installer \
  --system-extension-image ghcr.io/aarnaud-talos/intel-ucode:20240115 \
  --system-extension-image ghcr.io/aarnaud-talos/i915-ucode:20240115 \
  --system-extension-image ghcr.io/aarnaud-talos/applesmc-t2:${EXTENSION_VERSION}
xz -d _out/installer-amd64.tar.xz

crane push --platform linux/amd64 _out/installer-amd64.tar ghcr.io/aarnaud-talos/installer:${TALOS_VERSION}-applesmc-t2

docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal --output-kind iso \
  --system-extension-image ghcr.io/siderolabs/intel-ucode:20240115 \
  --system-extension-image ghcr.io/siderolabs/i915-ucode:20240115 \
  --system-extension-image ghcr.io/aarnaud-talos/applesmc-t2:${EXTENSION_VERSION}