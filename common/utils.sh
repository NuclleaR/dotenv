#!/bin/bash

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}
