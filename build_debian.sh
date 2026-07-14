yq_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}  # Default to amd64 if no architecture specified

if [ -z "$yq_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <yq_version> <build_version> [architecture]"
    echo "Example: $0 4.53.3 1 arm64"
    echo "Example: $0 4.53.3 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64, armhf, ppc64el, s390x, riscv64, i386, all"
    exit 1
fi

# Function to map Debian architecture to yq release asset name
get_yq_release() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "yq_linux_amd64"
            ;;
        "arm64")
            echo "yq_linux_arm64"
            ;;
        "armhf")
            echo "yq_linux_arm"
            ;;
        "ppc64el")
            echo "yq_linux_ppc64le"
            ;;
        "s390x")
            echo "yq_linux_s390x"
            ;;
        "riscv64")
            echo "yq_linux_riscv64"
            ;;
        "i386")
            echo "yq_linux_386"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local yq_release

    yq_release=$(get_yq_release "$build_arch")
    if [ -z "$yq_release" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64, armhf, ppc64el, s390x, riscv64, i386"
        return 1
    fi

    echo "Building for architecture: $build_arch using $yq_release"

    # Clean up any previous builds for this architecture
    rm -f "$yq_release" "${yq_release}.tar.gz" yq.1 install-man-page.sh || true

    # Download and extract the yq tarball (binary + man page) for this architecture
    if ! wget -q "https://github.com/mikefarah/yq/releases/download/v${yq_VERSION}/${yq_release}.tar.gz"; then
        echo "❌ Failed to download yq tarball for $build_arch"
        return 1
    fi

    if ! tar -xf "${yq_release}.tar.gz"; then
        echo "❌ Failed to extract yq tarball for $build_arch"
        return 1
    fi

    rm -f "${yq_release}.tar.gz"

    # Build packages for appropriate Debian distributions
    # riscv64 is only supported in trixie (v13) and later, not in bookworm (v12)
    if [ "$build_arch" = "riscv64" ]; then
        declare -a arr=("trixie" "forky" "sid")
    else
        declare -a arr=("bookworm" "trixie" "forky" "sid")
    fi

    for dist in "${arr[@]}"; do
        FULL_VERSION="$yq_VERSION-${BUILD_VERSION}~${dist}_${build_arch}"
        echo "  Building $FULL_VERSION"

        if ! docker build . -t "yq-$dist-$build_arch" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg yq_VERSION="$yq_VERSION" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch" \
            --build-arg YQ_RELEASE="$yq_release"; then
            echo "❌ Failed to build Docker image for $dist on $build_arch"
            return 1
        fi

        id="$(docker create "yq-$dist-$build_arch")"
        if ! docker cp "$id:/yq_$FULL_VERSION.deb" - > "./yq_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb package for $dist on $build_arch"
            return 1
        fi

        if ! tar -xf "./yq_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb contents for $dist on $build_arch"
            return 1
        fi
    done

    # Clean up extracted files
    rm -f "$yq_release" yq.1 install-man-page.sh || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building yq $yq_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    ARCHITECTURES=("amd64" "arm64" "armhf" "ppc64el" "s390x" "riscv64" "i386")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la yq_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi
