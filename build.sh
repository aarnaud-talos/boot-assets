#/bin/bash
set -e

# install crane
apt-get install -y jq make
CRANE_VERSION=$(curl -s "https://api.github.com/repos/google/go-containerregistry/releases/latest" | jq -r '.tag_name')
curl -sL "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" > go-containerregistry.tar.gz
tar -zxvf go-containerregistry.tar.gz -C /usr/local/bin/ crane && rm go-containerregistry.tar.gz

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


IMAGER_ARGS="--system-extension-image ghcr.io/aarnaud-talos/intel-ucode:20231114 \
              --system-extension-image ghcr.io/aarnaud-talos/i915-ucode:20240115 \
              --system-extension-image ghcr.io/aarnaud-talos/iscsi-tools:v0.1.4 \
              --system-extension-image ghcr.io/aarnaud-talos/thunderbolt:${EXTENSION_VERSION} \
              --system-extension-image ghcr.io/aarnaud-talos/util-linux-tools:${EXTENSION_VERSION} \
              --system-extension-image ghcr.io/aarnaud-talos/zfs:2.1.14-${EXTENSION_VERSION} \
              --system-extension-image ghcr.io/aarnaud-talos/applesmc-t2:${EXTENSION_VERSION}"

# Installer
docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal \
  --output-kind installer ${IMAGER_ARGS}
xz -d _out/installer-amd64.tar.xz
/usr/local/bin/crane push --platform linux/amd64 _out/installer-amd64.tar ghcr.io/aarnaud-talos/installer:${TALOS_VERSION}-applesmc-t2

# ISO
docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal \
  --output-kind iso ${IMAGER_ARGS}

# Kernel
docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal \
  --output-kind kernel ${IMAGER_ARGS}


# initramfs failed because xz
#docker run --rm -t -v $PWD/_out:/out ghcr.io/aarnaud-talos/imager:${TALOS_VERSION} metal \
#  --output-kind initramfs ${IMAGER_ARGS}