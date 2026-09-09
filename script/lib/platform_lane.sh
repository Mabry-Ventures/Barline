#!/usr/bin/env bash

# These checks classify observed versions only; they do not constitute proof
# that any application behavior passed on the runtime.
barline_is_macos27_runtime() {
    [[ "$1" =~ ^27\.[0-9]+(\.[0-9]+)?$ ]]
}

barline_is_xcode27_toolchain() {
    [[ "$1" =~ ^Xcode\ 27(\.[0-9]+)?([[:space:]]|$) ]]
}
