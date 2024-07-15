#!/usr/bin/env bash
set -eou pipefail

SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
CONFIG_FILE="$SCRIPT_PATH/baseline.conf"
APPLICATION_NAME="acmeair-nodejs"
LOAD_GENERATOR_LOC="$HOME/load_generator"
JAR_NAME="httploadgenerator.jar"
PORT="9080"

parse_config() {
	while IFS=$'[ \t]*=[ \t]*' read -r name value; do
		if [ -z "$name" ]; then
			continue
		fi
		case "$name" in
		server_ip)
			server_ip="$value"
			;;
		timeout_ms)
			timeout_ms="$value"
			;;
		profile)
			profile="$value"
			;;
		threads)
			threads="$value"
			;;
		virtual_users)
			virtual_users="$value"
			;;
		warmup_duration_sec)
			warmup_duration_sec="$value"
			;;
		warmup_rps)
			warmup_rps="$value"
			;;
		warmup_pause_sec)
			warmup_pause_sec="$value"
			;;
		*)
			printf "unknown configuration %s\n" "$name" >&2
			exit 1
			;;
		esac
	done <"$CONFIG_FILE"

	local exit_code=0

	log_fatal() {
		local name="$1"
		local option="$2"

		printf "failed to parse configuration file %s: %s must be set using %s\n" "$CONFIG_FILE" "$name" "$option"
		exit_code=1
	}

	if [ -z "$server_ip" ]; then
		log_fatal "server ip" "server_ip"
	fi
	if [ -z "$timeout_ms" ]; then
		log_fatal "timeout" "timeout_ms"
	fi
	if [ -z "$profile" ]; then
		log_fatal "workload" "workload"
	fi
	if [ -z "$threads" ]; then
		log_fatal "threads" "threads"
	fi
	if [ -z "$virtual_users" ]; then
		log_fatal "virtual users" "virtual_users"
	fi
	if [ -z "$warmup_duration_sec" ]; then
		log_fatal "warmup duration" "warmup_duration_sec"
	fi
	if [ -z "$warmup_rps" ]; then
		log_fatal "warmup RPS" "warmup_rps"
	fi
	if [ -z "$warmup_pause_sec" ]; then
		log_fatal "warmup pause" "warmup_pause_sec"
	fi

	return $exit_code
}

execute_remote_commands() {
	local user="$1"
	shift
	local ip="$1"
	shift
	local cmds=""
	while IFS= read -r cmd; do
		cmds+="$cmd; "
	done < <(printf "%s\n" "$@")
	ssh "$user"@"$ip" bash <<<"$cmds"
}

copy_file() {
	local src="$1"
	local dst="$2"
	if [ ! -f "$dst" ]; then
		cp "$src" "$dst"
	fi
}

get_start_time() {
	printf "%s" "$(date +%s)"
}

set_measurment_dir() {
	measurements_dir="$HOME/measurements/interference/benchmark-$(get_start_time)"
}

set_prometheus_volume_name() {
	volume_name="prometheus-data-$(get_start_time)"
}

setup_prometheus_volumes() {
	local cmds=(
		"docker volume create $volume_name >/dev/null"
		"cd \$HOME/$APPLICATION_NAME"
		"echo \"MG_PROMETHEUS_VOLUME_NAME=$volume_name\" >.env"
	)
	execute_remote_commands "$user" "$server_ip" "${cmds[@]}"
}

save_config() {
	local out="$1"
	local config_file
	config_file="$out/config.yml"
	local duration
	duration=$(wc -l <"$profile")
	duration=$(echo "$duration" | xargs)
	printf "Saving benchmark configuration to %s\n" "$config_file" >&2
	printf "duration: %d\n" "$duration" >"$config_file"
	{
		printf "timeout: %d\n" "$timeout_ms"
		printf "profile: %s\n" "$profile"
		printf "threads: %d\n" "$threads"
		printf "virtual_users: %d\n" "$virtual_users"
		printf "warmup_duration: %d\n" "$warmup_duration_sec"
		printf "warmup_rps: %d\n" "$warmup_rps"
		printf "warmup_pause: %d\n" "$warmup_pause_sec"
	} >>"$config_file"
}

setup() {
	set_measurment_dir
	set_prometheus_volume_name
	mkdir -p "$measurements_dir"

	setup_prometheus_volumes

	copy_file "$LOAD_GENERATOR_LOC/$JAR_NAME" "$SCRIPT_PATH/$JAR_NAME"
	save_config "$measurements_dir"
}

benchmark() {

	local start_cmds=(
		"cd \$HOME/$APPLICATION_NAME"
		"docker compose up --build --detach --force-recreate --wait --quiet-pull 2>/dev/null >&2"
	)
	execute_remote_commands "$user" "$server_ip" "${start_cmds[@]}"

	printf "Loading database...\n" >&2

	curl "http://$server_ip:$PORT/rest/api/loader/load"

	local yaml_file
	yaml_file=$(mktemp)
	sed -e 's/{{ACMEAIR_WEB_HOST}}/'"$server_ip"':'"$PORT"'/g' "$SCRIPT_PATH/workload.yml" >"$yaml_file"
	YAML_PATH="$yaml_file" \
		BENCHMARK_RUN="$measurements_dir" \
		PROFILE="$SCRIPT_PATH/$profile" \
		THREADS="$threads" \
		VIRTUAL_USERS="$virtual_users" \
		TIMEOUT="$timeout_ms" \
		WARMUP_DURATION="$warmup_duration_sec" \
		WARMUP_RPS="$warmup_rps" \
		WARMUP_PAUSE="$warmup_pause_sec" \
		docker compose up \
		--build --abort-on-container-exit --force-recreate

	local stop_cmds=(
		"cd \$HOME/$APPLICATION_NAME"
		"docker compose down -v 2>/dev/null >&2"
	)
	execute_remote_commands "$user" "$server_ip" "${stop_cmds[@]}"
	rm "$yaml_file"
}

collect_prometheus_metrics() {
	local cmds=(
		"rm /tmp/metrics.tar.gz 2>/dev/null"
		"docker run --rm -v /tmp:/backup -v $volume_name:/data busybox tar -czf /backup/metrics.tar.gz /data/"
	)
	execute_remote_commands "$user" "$server_ip" "${cmds[@]}"
	scp "$user"@"$server_ip":/tmp/metrics.tar.gz "$measurements_dir/metrics.tar.gz"
}

main() {
	user="$USER"

	parse_config
	setup
	benchmark
	collect_prometheus_metrics
}

main
