# refute_equal - Assert two values are NOT equal
# WHY: bats-assert doesn't ship refute_equal; we need it in multiple test files
# Usage: refute_equal "$actual" "$unexpected"
refute_equal() {
    if [ "$1" = "$2" ]; then
        echo "Expected values to differ, but both are: $1" >&2
        return 1
    fi
    return 0
}
