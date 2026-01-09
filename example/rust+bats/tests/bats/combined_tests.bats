#!/usr/bin/env bats

@test "combined project arithmetic" {
    result=$((3 + 4))
    [ "$result" -eq 7 ]
}

@test "combined project string test" {
    [ "suitey" = "suitey" ]
}
