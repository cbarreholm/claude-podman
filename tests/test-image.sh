#!/bin/bash
set -euo pipefail

IMAGE="localhost/opencode:${1:-latest}"
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

# 2. opencode binary runs and outputs a version
test_opencode_version() {
	local output
	output=$(podman run --rm --entrypoint "" "$IMAGE" \
		/usr/local/bin/opencode --version 2>&1)
	echo "$output" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'
}
run_test "opencode binary outputs version" \
	test_opencode_version

# 3. Entrypoint is set correctly
test_entrypoint() {
	local entrypoint
	entrypoint=$(podman inspect --format '{{range .Config.Entrypoint}}{{.}}{{end}}' "$IMAGE")
	[ "$entrypoint" = "/usr/local/bin/opencode" ]
}
run_test "Entrypoint is /usr/local/bin/opencode" \
	test_entrypoint

# 4. opencode user exists with UID 1000
test_opencode_uid() {
	local output
	output=$(podman run --rm --entrypoint "" "$IMAGE" id opencode 2>&1)
	echo "$output" | grep -q "uid=1000"
}
run_test "opencode user has UID 1000" \
	test_opencode_uid

# 5. Autoupdate is disabled via environment
test_autoupdate_env() {
	podman inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$IMAGE" |
		grep -q '^OPENCODE_DISABLE_AUTOUPDATE=true$'
}
run_test "OPENCODE_DISABLE_AUTOUPDATE is set" \
	test_autoupdate_env

# 6. Baked-in config disables autoupdate
test_autoupdate_config() {
	local output
	output=$(podman run --rm --entrypoint "" "$IMAGE" \
		cat /home/opencode/.config/opencode/opencode.json 2>&1)
	echo "$output" | grep -q '"autoupdate": false'
}
run_test "Image config sets autoupdate false" \
	test_autoupdate_config

# 7. Binary is root-owned so it cannot replace itself
test_binary_owner() {
	local output
	output=$(podman run --rm --entrypoint "" "$IMAGE" \
		stat -c '%U' /usr/local/bin/opencode 2>&1)
	[ "$output" = "root" ]
}
run_test "opencode binary is owned by root" \
	test_binary_owner

# 8. Wrapper script starts opencode and it responds
test_wrapper() {
	local output
	output=$(timeout 30 ./bin/opencode --local --version 2>&1)
	echo "$output" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'
}
run_test "Wrapper script starts opencode" \
	test_wrapper

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
