# OpenDiscourse Test Data Management

This document describes how test data is managed in the OpenDiscourse platform.

## Test Data Strategy

### Data Isolation
- Each test runs in an isolated environment
- Test data is separate from development and production data
- Clean state is ensured before each test

### Data Lifecycle
1. **Setup**: Test data is created or loaded
2. **Execution**: Tests run against the test data
3. **Teardown**: Test data is cleaned up

### Data Sources
- **Static fixtures**: Predefined test data
- **Dynamic generation**: Programmatically generated test data
- **Realistic samples**: Anonymized production data samples

## Test Data Types

### Unit Test Data
```python
# Simple, focused test data
test_user = {
    "id": 1,
    "name": "Test User",
    "email": "test@example.com"
}
```

### Integration Test Data
```python
# More complex, realistic test data
test_document = {
    "id": "doc_123",
    "title": "Test Document",
    "content": "This is a test document content.",
    "author_id": 1,
    "created_at": "2023-01-01T00:00:00Z"
}
```

### End-to-End Test Data
```python
# Complete workflow test data
test_workflow = {
    "name": "Document Processing Workflow",
    "steps": [
        {"name": "Upload Document", "action": "upload"},
        {"name": "Process Text", "action": "process"},
        {"name": "Generate Embeddings", "action": "embed"}
    ]
}
```

## Test Data Generation

### Static Fixtures
Located in `tests/fixtures/` directory:

```python
# tests/fixtures/users.py
TEST_USERS = [
    {
        "id": 1,
        "username": "testuser1",
        "email": "test1@example.com",
        "password": "testpassword123"
    },
    {
        "id": 2,
        "username": "testuser2",
        "email": "test2@example.com",
        "password": "testpassword456"
    }
]
```

### Dynamic Data Generation
```python
# Generate realistic test data
import faker

fake = faker.Faker()

def generate_test_user():
    return {
        "id": fake.uuid4(),
        "username": fake.user_name(),
        "email": fake.email(),
        "password": fake.password()
    }

def generate_test_document():
    return {
        "id": fake.uuid4(),
        "title": fake.sentence(),
        "content": fake.text(),
        "author_id": fake.uuid4(),
        "created_at": fake.iso8601()
    }
```

### Factory Pattern
```python
# tests/factories/user_factory.py
class UserFactory:
    @staticmethod
    def create(**kwargs):
        defaults = {
            "id": str(uuid.uuid4()),
            "username": fake.user_name(),
            "email": fake.email(),
            "password": fake.password()
        }
        defaults.update(kwargs)
        return defaults
    
    @staticmethod
    def create_batch(count, **kwargs):
        return [UserFactory.create(**kwargs) for _ in range(count)]
```

## Test Data Loading

### Database Seeding
```python
# Load test data into database
def seed_test_database():
    users = UserFactory.create_batch(10)
    for user in users:
        db.create_user(user)
    
    documents = [DocumentFactory.create(author_id=user["id"]) for user in users[:5]]
    for document in documents:
        db.create_document(document)
```

### API Data Loading
```python
# Load test data via API
def load_test_data_via_api():
    user_data = UserFactory.create()
    response = api_client.post("/users", json=user_data)
    assert response.status_code == 201
    
    document_data = DocumentFactory.create(author_id=user_data["id"])
    response = api_client.post("/documents", json=document_data)
    assert response.status_code == 201
```

## Test Data Cleanup

### Automatic Cleanup
```python
# pytest fixture for automatic cleanup
@pytest.fixture
def test_user():
    user = UserFactory.create()
    db.create_user(user)
    yield user
    db.delete_user(user["id"])
```

### Manual Cleanup
```python
# Explicit cleanup in tests
def test_user_creation():
    user = UserFactory.create()
    try:
        result = user_service.create_user(user)
        assert result is not None
    finally:
        user_service.delete_user(user["id"])
```

### Bulk Cleanup
```python
# Cleanup all test data
def cleanup_test_data():
    db.delete_all_test_users()
    db.delete_all_test_documents()
    db.reset_auto_increment()
```

## Test Data Security

### Data Anonymization
```python
# Anonymize sensitive test data
def anonymize_user_data(user):
    return {
        "id": user["id"],
        "username": user["username"],
        "email": f"test+{user['id']}@example.com",  # Anonymized email
        "password": "testpassword"  # Standard test password
    }
```

### Secure Test Credentials
```python
# Use secure, non-production credentials
TEST_CREDENTIALS = {
    "database_url": "postgresql://test:test@localhost:5433/testdb",
    "api_key": "test_api_key_1234567890",
    "jwt_secret": "test_jwt_secret_with_at_least_32_characters"
}
```

### Credential Management
```python
# Load credentials from secure environment
import os

def get_test_credentials():
    return {
        "database_url": os.getenv("TEST_DATABASE_URL", "postgresql://test:test@localhost:5433/testdb"),
        "api_key": os.getenv("TEST_API_KEY", "test_api_key_1234567890"),
        "jwt_secret": os.getenv("TEST_JWT_SECRET", "test_jwt_secret_with_at_least_32_characters")
    }
```

## Test Data Performance

### Efficient Data Loading
```python
# Batch insert for better performance
def load_test_users_batch(users):
    db.batch_insert_users(users)

# Use transactions for faster operations
def load_test_data_with_transaction():
    with db.transaction():
        users = UserFactory.create_batch(1000)
        load_test_users_batch(users)
```

### Data Caching
```python
# Cache frequently used test data
@pytest.fixture(scope="session")
def cached_test_users():
    if not hasattr(cached_test_users, "_data"):
        cached_test_users._data = UserFactory.create_batch(100)
    return cached_test_users._data
```

## Test Data Validation

### Data Integrity Checks
```python
# Validate test data before use
def validate_test_user(user):
    assert "id" in user
    assert "username" in user
    assert "email" in user
    assert "@" in user["email"]
    assert len(user["username"]) > 0

def validate_test_document(document):
    assert "id" in document
    assert "title" in document
    assert "content" in document
    assert len(document["title"]) > 0
    assert len(document["content"]) > 0
```

### Schema Validation
```python
# Validate test data against schemas
import jsonschema

USER_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "username": {"type": "string", "minLength": 1},
        "email": {"type": "string", "format": "email"}
    },
    "required": ["id", "username", "email"]
}

def validate_user_schema(user):
    jsonschema.validate(user, USER_SCHEMA)
```

## Test Data Documentation

### Test Data Dictionary
```markdown
# Test Data Dictionary

## Users
- `id`: Unique identifier (UUID)
- `username`: User's username (string, 1-50 chars)
- `email`: User's email (string, valid email format)
- `password`: User's password (string, 8+ chars)

## Documents
- `id`: Unique identifier (UUID)
- `title`: Document title (string, 1-200 chars)
- `content`: Document content (string, 1+ chars)
- `author_id`: Reference to user ID (UUID)
- `created_at`: Creation timestamp (ISO 8601)
```

### Data Lineage
```python
# Track test data lineage
TEST_DATA_LINEAGE = {
    "users": {
        "source": "UserFactory",
        "generation_date": "2023-01-01",
        "version": "1.0"
    },
    "documents": {
        "source": "DocumentFactory",
        "generation_date": "2023-01-01",
        "version": "1.0"
    }
}
```

## Best Practices

### Data Management
1. **Keep test data minimal**: Only include data needed for tests
2. **Use realistic data**: Make test data representative of real usage
3. **Maintain data consistency**: Ensure relationships between test data are valid
4. **Clean up after tests**: Always clean up test data to prevent test pollution

### Performance Optimization
1. **Batch operations**: Use batch inserts/updates when possible
2. **Caching**: Cache frequently used test data
3. **Selective loading**: Load only the data needed for specific tests
4. **Parallel execution**: Design tests to run in parallel when possible

### Security Considerations
1. **Never use real data**: Always use synthetic or anonymized test data
2. **Secure credentials**: Use separate, non-production credentials for testing
3. **Regular rotation**: Rotate test credentials regularly
4. **Access control**: Limit access to test data and environments

### Maintainability
1. **Clear naming**: Use descriptive names for test data
2. **Documentation**: Document test data structures and usage
3. **Versioning**: Version test data schemas when they change
4. **Automation**: Automate test data generation and cleanup