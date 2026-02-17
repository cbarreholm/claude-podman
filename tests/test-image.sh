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

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
