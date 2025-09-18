# OpenDiscourse Backend Tests

This directory contains tests for backend services and APIs.

## Test Categories

- `test_supabase.py` - Test Supabase services
- `test_apis.py` - Test REST API endpoints
- `test_database.py` - Test database operations
- `test_authentication.py` - Test authentication services
- `test_storage.py` - Test file storage services

## Running Backend Tests

```bash
# Run all backend tests
pytest tests/backend/

# Run specific backend test
pytest tests/backend/test_supabase.py

# Run with service dependencies
pytest tests/backend/ --with-services
```

## Test Environment

Backend tests require:
- Database services running
- API services accessible
- Test environment variables configured
- Proper service dependencies

## Test Data

Backend tests use:
- Test databases with sample data
- Mock external service responses
- Test user accounts and permissions
- Isolated test environments