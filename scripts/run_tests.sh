#!/bin/bash
"""
Test runner script for OpenDiscourse.
"""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Running OpenDiscourse Test Suite${NC}"

# Check if pytest is installed
if ! command -v pytest &> /dev/null; then
    echo -e "${YELLOW}Installing test dependencies...${NC}"
    pip install -r tests/requirements-test.txt
fi

# Run tests with different markers
echo -e "${GREEN}Running unit tests...${NC}"
pytest -m "not integration and not e2e" --tb=short -v

echo -e "${GREEN}Running integration tests...${NC}"
pytest -m "integration" --tb=short -v

echo -e "${GREEN}Running end-to-end tests...${NC}"
pytest -m "e2e" --tb=short -v

echo -e "${GREEN}All tests completed!${NC}"