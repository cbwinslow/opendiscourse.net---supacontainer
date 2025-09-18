# OpenDiscourse Network Tests

This directory contains tests for network connectivity, service communication, and API endpoints.

## Test Categories

- `test_connectivity.py` - Test network connectivity between services
- `test_api_endpoints.py` - Test REST API endpoints
- `test_websocket.py` - Test WebSocket connections
- `test_dns.py` - Test DNS resolution
- `test_firewall.py` - Test firewall configurations

## Running Network Tests

```bash
# Run all network tests
pytest tests/network/

# Run specific network test
pytest tests/network/test_connectivity.py

# Run with network simulation
pytest tests/network/ --simulate-network-conditions
```

## Test Environment

Network tests require:
- Services running on localhost or test environment
- Network access to service ports
- Proper firewall configurations

## Test Data

Network tests use:
- Mock HTTP servers for testing endpoints
- Simulated network conditions (latency, packet loss)
- Real service endpoints when available