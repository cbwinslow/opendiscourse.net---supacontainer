# OpenDiscourse Frontend Tests

This directory contains tests for the Next.js frontend application.

## Test Categories

- `test_components.py` - Test React components
- `test_pages.py` - Test Next.js pages
- `test_authentication.py` - Test authentication flows
- `test_routing.py` - Test client-side routing
- `test_api_integration.py` - Test frontend-to-backend integration

## Running Frontend Tests

```bash
# Run all frontend tests
pytest tests/frontend/

# Run specific frontend test
pytest tests/frontend/test_components.py

# Run with browser automation
pytest tests/frontend/ --browser=chrome
```

## Test Environment

Frontend tests require:
- Node.js and pnpm installed
- Next.js application built
- Test server running
- Browser drivers for UI tests

## Test Data

Frontend tests use:
- Mock API responses
- Test user accounts
- Sample data for UI components
- Browser automation tools (Playwright/Selenium)