#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

IMAGE="docker.io/library/pytorch:latest"
DOCKERFILE="${SCRIPT_PATH}/pytorch_dockerfile/Dockerfile"
pytorch_file=$(mktemp pytorchresults.XXXXXXXXXX)
NUM_CONTAINERS="$1"
TIMEOUT="$2"
TEST_NAME="pytorch"
CMD_RUN="cd pyhpc-benchmarks-3.0 && python run.py benchmarks/equation_of_state --burnin 20 --device cpu -b pytorch -s 524288 > LOG"
CMD_RESULT="cd pyhpc-benchmarks-3.0 && cat LOG"
CMD_FILE="cat pyhpc-benchmarks-3.0/LOG | grep 'seconds' | wc -l"
PAYLOAD_ARGS="tail -f /dev/null"

function remove_tmp_file() {
	rm -rf "${pytorch_file}"
}

trap remove_tmp_file EXIT

function check_containers_are_up() {
	local containers_launched=0
	for i in $(seq "${TIMEOUT}") ; do
		info "Verify that the containers are running"
		containers_launched="$(sudo ${CTR_EXE} t list | grep -c "RUNNING")"
		[ "${containers_launched}" -eq "${NUM_CONTAINERS}" ] && break
		sleep 1
		[ "${i}" == "${TIMEOUT}" ] && return 1
	done
}

function pytorch_test() {
	info "Running Pytorch test"
	for i in "${containers[@]}"; do
		sudo -E "${CTR_EXE}" t exec -d --exec-id "$(random_name)" "${i}" sh -c "${CMD_RUN}"
	done

	for i in "${containers[@]}"; do
		check_file=$(sudo -E "${CTR_EXE}" t exec --exec-id "$(random_name)" "${i}" sh -c "${CMD_FILE}")
		retries="200"
		for j in $(seq 1 "${retries}"); do
			[ "${check_file}" -eq 1 ] && break
			sleep 1
		done
	done

	for i in "${containers[@]}"; do
		sudo -E "${CTR_EXE}" t exec --exec-id "$(random_name)" "${i}" sh -c "${CMD_RESULT}"  >> "${pytorch_file}"
	done

	local pytorch_results=$(cat "${pytorch_file}" | grep pytorch | sed '/Using pytorch version/d' | awk '{print $4}' | tr '\n' ',' | sed 's/.$//')
	local average_pytorch=$(echo "${pytorch_results}" | sed "s/,/+/g;s/.*/(&)\/$NUM_CONTAINERS/g" | bc -l)

	local json="$(cat << EOF
	{
		"Pytorch": {
			"Result": "${pytorch_results}",
			"Average": "${average_pytorch}",
			"Units": "s"
		}
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"

}

function main() {
	# Verify enough arguments
	if [ $# != 2 ]; then
		echo >&2 "error: Not enough arguments [$@]"
		help
		exit 1
	fi

	local i=0
	local containers=()
	local not_started_count="${NUM_CONTAINERS}"

	# Check tools/commands dependencies
	cmds=("awk" "docker" "bc")
	check_cmds "${cmds[@]}"
	check_ctr_images "${IMAGE}" "${DOCKERFILE}"

	init_env
	info "Creating ${NUM_CONTAINERS} containers"

	for ((i=1; i<= "${NUM_CONTAINERS}"; i++)); do
		containers+=($(random_name))
		sudo -E "${CTR_EXE}" run -d --runtime "${CTR_RUNTIME}" "${IMAGE}" "${containers[-1]}" sh -c "${PAYLOAD_ARGS}"
		((not_started_count--))
		info "$not_started_count remaining containers"
	done

	metrics_json_init
	metrics_json_start_array


	# Check that the requested number of containers are running
	check_containers_are_up

	pytorch_test

	metrics_json_save

	clean_env_ctr

}
main "$@"
