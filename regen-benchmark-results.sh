#!/bin/bash
set -e

cabal run streaming-async-bench -- --output benchmark-results.html
