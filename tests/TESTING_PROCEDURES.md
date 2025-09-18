# OpenDiscourse Testing Procedures

This document outlines the testing procedures for the OpenDiscourse platform.

## Test Execution Procedures

### 1. Pre-Test Setup

#### Environment Preparation
1. Create a virtual environment:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

2. Install test dependencies:
   ```bash
   pip install -r tests/requirements-test.txt
   ```

3. Ensure Docker is running:
   ```bash
   docker info
   ```

4. Verify Node.js and pnpm are installed:
   ```bash
   node --version
   pnpm --version
   ```

### 2. Unit Test Execution

#### Run All Unit Tests
```bash
pytest tests/unit/ -v
```

#### Run Specific Unit Test
```bash
pytest tests/unit/test_utilities.py::TestEnvironmentGeneration::test_generate_secure_password_default -v
```

#### Unit Test Coverage
```bash
pytest tests/unit/ --cov=scripts --cov-report=html
```

### 3. Integration Test Execution

#### Run All Integration Tests
```bash
pytest tests/integration/ -v
```

#### Run Specific Integration Test
```bash
pytest tests/integration/test_services.py::TestServiceIntegration::test_supabase_nextjs_integration -v
```

### 4. Docker Test Execution

#### Run All Docker Tests
```bash
pytest tests/docker/ -v
```

#### Run Docker Tests with Services
```bash
pytest tests/docker/ --docker-compose up
```

### 5. Network Test Execution

#### Run All Network Tests
```bash
pytest tests/network/ -v
```

#### Run Network Tests with Simulation
```bash
pytest tests/network/ --simulate-network-conditions
```

### 6. Frontend Test Execution

#### Run All Frontend Tests
```bash
pytest tests/frontend/ -v
```

#### Run Frontend Tests with Browser
```bash
pytest tests/frontend/ --browser=chrome
```

### 7. Backend Test Execution

#### Run All Backend Tests
```bash
pytest tests/backend/ -v
```

#### Run Backend Tests with Services
```bash
pytest tests/backend/ --with-services
```

### 8. End-to-End Test Execution

#### Run All E2E Tests
```bash
pytest tests/e2e/ -v
```

#### Run Specific E2E Test
```bash
pytest tests/e2e/test_workflows.py::TestDeploymentWorkflows::test_one_click_deploy_script_exists -v
```

## Test Data Management

### Test Environment Variables
- Use `.env.test` for test-specific environment variables
- Isolate test environments from development environments
- Clean up test data after test execution

### Test Database
- Use separate test databases
- Seed test data before tests
- Clean up test data after tests

### Test Containers
- Use temporary Docker containers for tests
- Clean up containers after tests
- Isolate test networks

## Continuous Integration

### GitHub Actions Workflow
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: 3.9
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r tests/requirements-test.txt
    - name: Run tests
      run: pytest
```

### Test Reporting
- Generate HTML test reports
- Upload test results to CI/CD
- Send notifications on test failures

## Test Maintenance

### Regular Test Updates
- Update tests when code changes
- Add new tests for new features
- Remove obsolete tests

### Test Performance
- Monitor test execution times
- Optimize slow tests
- Parallelize test execution when possible

### Test Coverage
- Maintain high test coverage
- Identify untested code paths
- Add tests for critical functionality

## Troubleshooting

### Common Test Issues
1. **Docker not available**: Ensure Docker daemon is running
2. **Network connectivity**: Check firewall and network settings
3. **Missing dependencies**: Install required packages
4. **Port conflicts**: Stop conflicting services

### Debugging Failed Tests
1. Run failed test in isolation:
   ```bash
   pytest tests/unit/test_utilities.py::TestEnvironmentGeneration::test_generate_secure_password_default -v -s
   ```

2. Add debug output to tests
3. Use pytest fixtures for test setup
4. Check test logs and error messages

### Test Environment Issues
1. Clean test environment:
   ```bash
   docker system prune -f
   ```

2. Reset test databases
3. Restart test services
4. Verify environment variables