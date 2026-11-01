
#!/usr/bin/env bash
set -Eeuo pipefail

# *** configuration ***

ASEPRITE_REPO="https://github.com/aseprite/aseprite.git"
SKIA_BASE_URL="https://github.com/aseprite/skia/releases/download"

# *** dependencies ***

for cmd in git cmake ninja curl python3 unzip; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' not found"
        exit 1
    fi
done

# *** detect platform ***

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)
        PLATFORM="linux"
        ;;
    Darwin)
        PLATFORM="macos"
        ;;
    *)
        echo "ERROR: Unsupported platform: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        SKIA_ARCH="x64"
        ;;
    arm64|aarch64)
        SKIA_ARCH="arm64"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

if [[ "$PLATFORM" == "linux" && "$SKIA_ARCH" != "x64" ]]; then
    echo "ERROR: Linux ARM64 Skia builds are not configured."
    exit 1
fi

echo "Platform: $PLATFORM ($SKIA_ARCH)"

# *** clone aseprite repo ***

if [[ ! -d aseprite/.git ]]; then
    git clone --recursive --tags "$ASEPRITE_REPO" aseprite
else
    git -C aseprite fetch --tags
fi

# *** get version ***

if [[ -z "${ASEPRITE_VERSION:-}" ]]; then
    ASEPRITE_VERSION="$(
        git -C aseprite tag --sort=-version:refname |
        head -n 1
    )"
fi

if [[ -z "$ASEPRITE_VERSION" ]]; then
    echo "ERROR: Could not determine Aseprite version"
    exit 1
fi

echo "Building Aseprite $ASEPRITE_VERSION"

# *** update aseprite repo ***

git -C aseprite clean --quiet -fdx
git -C aseprite submodule foreach --recursive git clean -xfd

git -C aseprite fetch --quiet --depth=1 --no-tags origin \
    "$ASEPRITE_VERSION:refs/remotes/origin/$ASEPRITE_VERSION"

git -C aseprite reset --quiet --hard \
    "origin/$ASEPRITE_VERSION"

git -C aseprite submodule update --init --recursive

# *** patch version ***

python3 - "$ASEPRITE_VERSION" <<'PY'
import pathlib
import sys

version = sys.argv[1].lstrip("v")
path = pathlib.Path("aseprite/src/ver/CMakeLists.txt")

content = path.read_text()
path.write_text(content.replace("1.x-dev", version))
PY

# *** determine skia version ***

if [[ -f aseprite/laf/misc/skia-tag.txt ]]; then
    SKIA_VERSION="$(<aseprite/laf/misc/skia-tag.txt)"
elif [[ "$ASEPRITE_VERSION" == *beta* ]]; then
    SKIA_VERSION="m124-08a5439a6b"
else
    SKIA_VERSION="m102-861e4743af"
fi

echo "Skia version: $SKIA_VERSION"

# *** download skia ***

SKIA_DIR="$PWD/skia-$SKIA_VERSION"

if [[ ! -d "$SKIA_DIR" ]] || [[ ! -f "$SKIA_DIR/include/core/SkCanvas.h" ]]; then
    mkdir -p "$SKIA_DIR"

    case "$PLATFORM" in
        linux)
            SKIA_FILE="Skia-Linux-Release-x64.zip"
            ;;
        macos)
            if [[ "$SKIA_ARCH" == "arm64" ]]; then
                SKIA_FILE="Skia-macOS-Release-arm64.zip"
            else
                SKIA_FILE="Skia-macOS-Release-x64.zip"
            fi
            ;;
    esac

    SKIA_URL="$SKIA_BASE_URL/$SKIA_VERSION/$SKIA_FILE"

    echo "Downloading $SKIA_FILE"

    curl -fL "$SKIA_URL" -o "$SKIA_DIR/skia.zip"
    unzip -q -o "$SKIA_DIR/skia.zip" -d "$SKIA_DIR"
    rm "$SKIA_DIR/skia.zip"
fi

# *** configure compiler ***

if [[ "$PLATFORM" == "linux" ]]; then
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"

    CMAKE_PLATFORM_ARGS=(
        -DCMAKE_CXX_FLAGS:STRING=-stdlib=libstdc++
        -DCMAKE_EXE_LINKER_FLAGS:STRING=-stdlib=libstdc++
    )
else
    CMAKE_PLATFORM_ARGS=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
    )

    if [[ "$SKIA_ARCH" == "arm64" ]]; then
        CMAKE_PLATFORM_ARGS+=(
            -DCMAKE_OSX_ARCHITECTURES=arm64
            -DPNG_ARM_NEON:STRING=on
        )
        SKIA_LIBRARY_DIR="$SKIA_DIR/out/Release-arm64"
    else
        CMAKE_PLATFORM_ARGS+=(
            -DCMAKE_OSX_ARCHITECTURES=x86_64
        )
        SKIA_LIBRARY_DIR="$SKIA_DIR/out/Release-x64"
    fi
fi

if [[ "$PLATFORM" == "linux" ]]; then
    SKIA_LIBRARY_DIR="$SKIA_DIR/out/Release-x64"
fi

# *** build aseprite ***

rm -rf build

cmake \
    -G Ninja \
    -S aseprite \
    -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DENABLE_CCACHE=OFF \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="$SKIA_DIR" \
    -DSKIA_LIBRARY_DIR="$SKIA_LIBRARY_DIR" \
    "${CMAKE_PLATFORM_ARGS[@]}"

cmake --build build --parallel --target aseprite

# *** create output folder ***

OUTPUT_DIR="aseprite-$ASEPRITE_VERSION"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "# This file is here so Aseprite behaves as a portable program" \
    > "$OUTPUT_DIR/aseprite.ini"

cp -R aseprite/docs "$OUTPUT_DIR/docs"
cp -R build/bin/data "$OUTPUT_DIR/data"

cp build/bin/aseprite "$OUTPUT_DIR/aseprite"

# *** github actions ***

if [[ -n "${GITHUB_WORKFLOW:-}" ]]; then
    mkdir -p github
    mv "$OUTPUT_DIR" github/

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "ASEPRITE_VERSION=$ASEPRITE_VERSION" >> "$GITHUB_OUTPUT"
    fi
fi

echo "Successfully built Aseprite $ASEPRITE_VERSION"
