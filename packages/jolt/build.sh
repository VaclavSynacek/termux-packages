TERMUX_PKG_HOMEPAGE=https://github.com/jolt-lang/jolt
TERMUX_PKG_DESCRIPTION="A native Clojure implementation built on Chez Scheme"
TERMUX_PKG_LICENSE="EPL-2.0, EPL-1.0, Apache-2.0, MIT, BSD, BSD 2-Clause, ZLIB"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.8.20
TERMUX_PKG_SRCURL=git+https://github.com/jolt-lang/jolt.git
TERMUX_PKG_GIT_BRANCH="v${TERMUX_PKG_VERSION}"
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_DEPENDS="libiconv, liblz4, libuuid, ncurses, zlib"
# Native application builds need a C compiler; Git-backed deps need git.
TERMUX_PKG_RECOMMENDS="clang, git"
TERMUX_PKG_BUILD_DEPENDS="chez-scheme, chez-scheme-static"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_HOSTBUILD=true
# 32-bit builds succeed, but Jolt currently fails during runtime startup.
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686"
# Host compiler, xpatch and packaged target kernel must have matching versions.
_CHEZ_VERSION=10.4.1

termux_step_post_get_source() {
	case "${TERMUX_ARCH}" in
		aarch64) JOLT_MACHINE=tarm64le ;;
		x86_64) JOLT_MACHINE=ta6le ;;
	esac
	export JOLT_MACHINE
}

termux_step_host_build() {
	if [[ "${TERMUX_ON_DEVICE_BUILD}" == true ]]; then
		return
	fi
	# Only the build-host compiler is bootstrapped here. The Android kernel and
	# boot files come from the packaged chez-scheme / chez-scheme-static.
	local version="${_CHEZ_VERSION}"
	termux_download \
		"https://github.com/cisco/ChezScheme/releases/download/v${version}/csv${version}.tar.gz" \
		"${TERMUX_PKG_CACHEDIR}/csv${version}.tar.gz" \
		2e74952db7bc177f0c3602e2217a341ba677d733eec4cd7726418c3a4e1ef308
	mkdir -p chez-src
	tar -xf "${TERMUX_PKG_CACHEDIR}/csv${version}.tar.gz" -C chez-src --strip-components=1
	./chez-src/configure --disable-x11
	# Host-build artifacts are cached across target architectures.
	local machine
	for machine in tarm64le ta6le; do
		make -j "${TERMUX_PKG_MAKE_PROCESSES}" bootquick XM="$machine"
	done
}

termux_step_configure() {
	:
}

termux_step_make() {
	local csv="${TERMUX_PREFIX}/lib/csv${_CHEZ_VERSION}/${JOLT_MACHINE}"
	export JOLT_VERSION="${TERMUX_PKG_VERSION}"
	if [[ "${TERMUX_ON_DEVICE_BUILD}" == true ]]; then
		export JOLT_CHEZ="${TERMUX_PREFIX}/bin/chez"
		export JOLT_CHEZ_CSV="$csv"
		export JOLT_CC="$CC $CPPFLAGS $CFLAGS $LDFLAGS"
		"$JOLT_CHEZ" --script host/chez/build-jolt.ss release target/release/jolt
	else
		local host="${TERMUX_PKG_HOSTBUILD_DIR}"
		local host_machine
		host_machine=$(awk -F= '/^workarea=/{print $2}' "$host/Makefile")
		export JOLT_CHEZ="$host/$host_machine/bin/$host_machine/scheme"
		export SCHEMEHEAPDIRS="$host/$host_machine/boot/$host_machine"
		export JOLT_TARGET_PACK="${TERMUX_PKG_TMPDIR}/target-pack"
		export JOLT_TARGET_CC="$CC $CPPFLAGS $CFLAGS $LDFLAGS"
		# Android and Linux share Chez machine types. When host and target
		# match, Jolt uses its native path; supply the target overrides there too.
		export JOLT_CC="$JOLT_TARGET_CC"
		export JOLT_CHEZ_CSV="$csv"
		export JOLT_TARGET_LINK_LIBS="-liconv -lncurses -llz4 -lz -luuid -ldl -lm -pthread"
		mkdir -p "$JOLT_TARGET_PACK"
		cp "$csv/"{scheme.h,libkernel.a,petite.boot,scheme.boot} "$JOLT_TARGET_PACK/"
		cp "$host/xc-${JOLT_MACHINE}/s/xpatch" "$JOLT_TARGET_PACK/"
		printf '%s\n' "$JOLT_TARGET_LINK_LIBS" > "$JOLT_TARGET_PACK/link-libs"
		"$JOLT_CHEZ" --script host/chez/build-jolt.ss release target/release/jolt "$JOLT_MACHINE"
	fi
}

termux_step_make_install() {
	install -Dm700 target/release/jolt "${TERMUX_PREFIX}/bin/jolt"
	# The binary embeds third-party sources and the Chez kernel. Preserve
	# upstream's attribution inventory and all accompanying license texts.
	local doc="${TERMUX_PREFIX}/share/doc/jolt"
	mkdir -p "$doc"
	cp NOTICE "$doc/"
	cp -a licenses "$doc/"
}
