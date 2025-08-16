#!/bin/bash

# Test runner for OpenDiscourse

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPORT_DIR="$TEST_DIR/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PYTEST_OPTS="-v --cov=opendiscourse --cov-report=html --cov-report=xml"

# Create report directory
mkdir -p "$REPORT_DIR"

# Function to run tests
run_tests() {
    local test_type=$1
    local report_file="$REPORT_DIR/${test_type}_${TIMESTAMP}.xml"
    
    echo -e "${GREEN}Running ${test_type} tests...${NC}"
    
    cd "$TEST_DIR/.." || exit 1
    
    case $test_type in
        unit)
            pytest tests/unit/ $PYTEST_OPTS --junitxml="$report_file"
            ;;
        integration)
            docker-compose -f tests/docker-compose.test.yml up -d
            pytest tests/integration/ $PYTEST_OPTS --junitxml="$report_file"
            docker-compose -f tests/docker-compose.test.yml down
            ;;
        e2e)
            docker-compose -f tests/docker-compose.test.yml up -d
            pytest tests/e2e/ $PYTEST_OPTS --junitxml="$report_file"
            docker-compose -f tests/docker-compose.test.yml down
            ;;
        *)
            echo "Unknown test type: $test_type"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    # Install test dependencies
    echo -e "${GREEN}Installing test dependencies...${NC}"
    pip install -r tests/requirements.txt
    
    # Run tests
    for test_type in unit integration e2e; do
        if [ -d "tests/$test_type" ]; then
            run_tests "$test_type"
        fi
    done
    
    # Generate combined coverage report
    echo -e "${GREEN}Generating coverage report...${NC}"
    coverage combine
    coverage html -d "$REPORT_DIR/coverage"
    
    echo -e "${GREEN}All tests completed! Reports available in $REPORT_DIR${NC}"}

# Run main function
main "$@"
