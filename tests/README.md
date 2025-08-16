# OpenDiscourse Test Suite

This directory contains automated tests for the OpenDiscourse platform, including integration, unit, and end-to-end tests.

## Test Structure

```
tests/
├── integration/      # Integration tests
├── e2e/             # End-to-end tests
├── unit/            # Unit tests
├── fixtures/        # Test data and fixtures
└── utils/           # Test utilities
```

## Running Tests

### Prerequisites
- Python 3.8+
- Docker and Docker Compose
- Node.js 16+ (for frontend tests)

### Setup

1. Install test dependencies:
```bash
pip install -r tests/requirements.txt
npm install --prefix tests/e2e
```

2. Start the test environment:
```bash
docker-compose -f tests/docker-compose.test.yml up -d
```

### Running Tests

Run all tests:
```bash
pytest tests/
```

Run specific test suite:
```bash
pytest tests/unit/
pytest tests/integration/
npm test --prefix tests/e2e
```

## Writing Tests

- Place unit tests in `tests/unit/`
- Place integration tests in `tests/integration/`
- Place end-to-end tests in `tests/e2e/`
- Use fixtures from `tests/fixtures/` for test data

## Test Coverage

Generate coverage report:
```bash
pytest --cov=opendiscourse tests/
```

View coverage in browser:
```bash
python -m http.server --directory htmlcov
```
