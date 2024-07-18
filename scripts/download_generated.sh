#!/usr/bin/env bash
set -euo pipefail

log_fatal() {
	local msgs=("$@")
	printf "%s\n" "${msgs[@]}" >&2
	exit 1
}

log_info() {
	local msgs=("$@")
	printf "[INFO] %s\n" "${msgs[@]}" >&2
}

main() {
	local benchmark
	local user="$USER"
	local host
	local out="measurements"
	for opt in "$@"; do
		case "$opt" in
		--benchmark=*)
			benchmark="${opt#*=}"
			;;
		--user=*)
			user="${opt#*=}"
			;;
		--host=*)
			host="${opt#*=}"
			;;
		-*)
			log_fatal "unknown option: $opt"
			;;
		esac
		shift
	done

	local errors=()
	local errMsg="missing argument:"
	if [ -z "$benchmark" ]; then
		errors+=("$errMsg --benchmark")
	fi
	if [ -z "$host" ]; then
		errors+=("$errMsg --host")
	fi

	if [ "${#errors[@]}" -ne 0 ]; then
		log_fatal "${errors[@]}"
	fi

	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	(
		cd "$SCRIPT_PATH"
		local tar_archive="$benchmark.tar.gz"

		log_info "Archiving directory $benchmark into $tar_archive" "This may take a while..."
		ssh "$user@$host" "
cd $benchmark
tar -czf $tar_archive benchmarks"
		log_info "Copying $tar_archive from remote..."
		mkdir -p "../$out/$benchmark"
		scp "$user@$host:$benchmark/$tar_archive" "../$out/$benchmark/$tar_archive"
		cd "../$out/$benchmark"
		log_info "Extracting $tar_archive into $out/$benchmark"
		tar -xzf "$tar_archive"
		rm "$tar_archive"
		log_info "Successfully downloaded measurements for $benchmark"
	)
}

main "$@"
