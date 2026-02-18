#!/bin/bash
set -euo pipefail

IMAGE="localhost/claude-code:${1:-latest}"
PASS=0
FAIL=0

run_test() {
	local name="$1"
	shift
	printf "TEST: %s ... " "$name"
	if "$@"; then
		echo "PASS"
		PASS=$((PASS + 1))
	else
		echo "FAIL"
		FAIL=$((FAIL + 1))
	fi
}

# 1. Image exists
run_test "Image exists" \
	podman image exists "$IMAGE"

# 2. Claude binary runs and outputs a version
test_claude_version() {
	local output
	output=$(podman run --rm --entrypoint "" "$IMAGE" \
		/home/claude/.local/bin/claude --version 2>&1)
	echo "$output" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'
}
run_test "Claude binary outputs version" \
	test_claude_version

# 3. Entrypoint is set correctly
test_entrypoint() {
	local entrypoint
	entrypoint=$(podman inspect --format '{{range .Config.Entrypoint}}{{.}}{{end}}' "$IMAGE")
	[ "$entrypoint" = "/home/claude/.local/bin/claude" ]
}
run_test "Entrypoint is /home/claude/.local/bin/claude" \
	test_entrypoint

# 4. Claude user exists with UID 1000
test_claude_uid() {
	local output
	output=$(podman run --rm --entrypoint "" "$IMAGE" id claude 2>&1)
	echo "$output" | grep -q "uid=1000"
}
run_test "Claude user has UID 1000" \
	test_claude_uid

# 5. Wrapper script starts claude and it responds
test_wrapper() {
	local output
	output=$(timeout 30 ./bin/claude --local --version 2>&1)
	echo "$output" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'
}
run_test "Wrapper script starts claude" \
	test_wrapper

# 6. Restricted network: wrapper sets up proxy and blocks direct access
test_restricted_network() {
	# Capture the container name from stderr
	local stderr_file
	stderr_file=$(mktemp)

	# Run the wrapper in the background (it detaches the container, then attaches)
	./bin/claude --local --restricted-network 2>"$stderr_file" &
	local wrapper_pid=$!

	# Wait for the container name to appear in stderr
	local claude_container=""
	for i in $(seq 1 30); do
		claude_container=$(grep '^claudecode-' "$stderr_file" | head -1)
		[ -n "$claude_container" ] && break
		sleep 1
	done
	rm -f "$stderr_file"
	[ -z "$claude_container" ] && { kill "$wrapper_pid" 2>/dev/null; return 1; }

	# Verify HTTPS_PROXY is set
	local env_output
	env_output=$(podman exec "$claude_container" env 2>&1)

	# Verify direct external access is blocked
	local curl_blocked
	curl_blocked=$(podman exec "$claude_container" bash -c \
		"curl -s --connect-timeout 5 https://google.com 2>&1; echo exit_code=\$?" 2>&1)

	# Verify allowed domain is reachable via proxy
	local curl_allowed
	curl_allowed=$(podman exec "$claude_container" bash -c \
		"curl -s --connect-timeout 10 --proxy \$HTTPS_PROXY -o /dev/null -w '%{http_code}' https://claude.ai 2>&1; echo exit_code=\$?" 2>&1)

	# Cleanup: stop the container which triggers the wrapper's trap
	podman stop "$claude_container" >/dev/null 2>&1
	wait "$wrapper_pid" 2>/dev/null

	echo "$env_output" | grep -q "HTTPS_PROXY=http://.*:3128" || return 1
	echo "$curl_blocked" | grep -q "exit_code=0" && return 1
	echo "$curl_allowed" | grep -q "exit_code=0" || return 1
	return 0
}
run_test "Restricted network blocks direct access and sets proxy" \
	test_restricted_network

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
