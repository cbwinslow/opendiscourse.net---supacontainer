# OpenDiscourse Mock Data and Fixtures

This document describes the mock data and fixtures used in OpenDiscourse tests.

## Mock Data Structure

### User Mock Data
```python
# tests/mocks/users.py
"""Mock user data for testing."""

MOCK_USER = {
    "id": "user_1234567890",
    "username": "testuser",
    "email": "test@example.com",
    "password": "testpassword123",
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2023-01-01T00:00:00Z"
}

MOCK_USERS = [
    {
        "id": "user_1234567890",
        "username": "testuser1",
        "email": "test1@example.com",
        "password": "testpassword123",
        "created_at": "2023-01-01T00:00:00Z",
        "updated_at": "2023-01-01T00:00:00Z"
    },
    {
        "id": "user_0987654321",
        "username": "testuser2",
        "email": "test2@example.com",
        "password": "testpassword456",
        "created_at": "2023-01-02T00:00:00Z",
        "updated_at": "2023-01-02T00:00:00Z"
    }
]

MOCK_USER_PROFILE = {
    "id": "profile_1234567890",
    "user_id": "user_1234567890",
    "first_name": "Test",
    "last_name": "User",
    "bio": "This is a test user bio.",
    "avatar_url": "https://example.com/avatar.jpg",
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2023-01-01T00:00:00Z"
}
```

### Document Mock Data
```python
# tests/mocks/documents.py
"""Mock document data for testing."""

MOCK_DOCUMENT = {
    "id": "doc_1234567890",
    "title": "Test Document",
    "content": "This is a test document content with some meaningful text for processing.",
    "author_id": "user_1234567890",
    "status": "published",
    "tags": ["test", "document", "sample"],
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2023-01-01T00:00:00Z"
}

MOCK_DOCUMENTS = [
    {
        "id": "doc_1234567890",
        "title": "Test Document 1",
        "content": "This is the first test document content.",
        "author_id": "user_1234567890",
        "status": "published",
        "tags": ["test", "document"],
        "created_at": "2023-01-01T00:00:00Z",
        "updated_at": "2023-01-01T00:00:00Z"
    },
    {
        "id": "doc_0987654321",
        "title": "Test Document 2",
        "content": "This is the second test document content.",
        "author_id": "user_0987654321",
        "status": "draft",
        "tags": ["test", "draft"],
        "created_at": "2023-01-02T00:00:00Z",
        "updated_at": "2023-01-02T00:00:00Z"
    }
]

MOCK_DOCUMENT_CHUNK = {
    "id": "chunk_1234567890",
    "document_id": "doc_1234567890",
    "content": "This is a chunk of text from the document.",
    "embedding": [0.1, 0.2, 0.3, 0.4, 0.5],  # Simplified embedding
    "position": 0,
    "created_at": "2023-01-01T00:00:00Z"
}
```

### Authentication Mock Data
```python
# tests/mocks/auth.py
"""Mock authentication data for testing."""

MOCK_AUTH_SESSION = {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
    "refresh_token": "refresh_1234567890",
    "token_type": "bearer",
    "expires_in": 3600,
    "expires_at": 1641769200,
    "user": {
        "id": "user_1234567890",
        "aud": "authenticated",
        "role": "authenticated",
        "email": "test@example.com"
    }
}

MOCK_AUTH_RESPONSE = {
    "user": {
        "id": "user_1234567890",
        "aud": "authenticated",
        "role": "authenticated",
        "email": "test@example.com",
        "email_confirmed_at": "2023-01-01T00:00:00Z",
        "created_at": "2023-01-01T00:00:00Z"
    },
    "session": MOCK_AUTH_SESSION
}
```

## Mock Services

### Supabase Mock Client
```python
# tests/mocks/supabase.py
"""Mock Supabase client for testing."""

from unittest.mock import Mock, MagicMock

def create_mock_supabase_client():
    """Create a mock Supabase client."""
    mock_client = Mock()
    
    # Mock auth methods
    mock_auth = Mock()
    mock_auth.sign_up.return_value = {
        "user": {
            "id": "user_1234567890",
            "email": "test@example.com"
        },
        "session": None
    }
    
    mock_auth.sign_in_with_password.return_value = {
        "user": {
            "id": "user_1234567890",
            "email": "test@example.com"
        },
        "session": {
            "access_token": "test_access_token",
            "refresh_token": "test_refresh_token"
        }
    }
    
    mock_auth.sign_out.return_value = None
    mock_auth.get_user.return_value = {
        "user": {
            "id": "user_1234567890",
            "email": "test@example.com"
        }
    }
    
    mock_client.auth = mock_auth
    
    # Mock database methods
    mock_from = Mock()
    mock_from.select.return_value = MagicMock()
    mock_from.select.return_value.execute.return_value = {
        "data": [],
        "count": 0
    }
    
    mock_from.insert.return_value = MagicMock()
    mock_from.insert.return_value.execute.return_value = {
        "data": []
    }
    
    mock_client.from_ = Mock(return_value=mock_from)
    
    return mock_client
```

### HTTP Mock Responses
```python
# tests/mocks/http.py
"""Mock HTTP responses for testing."""

MOCK_HTTP_SUCCESS = {
    "status_code": 200,
    "json": lambda: {"success": True},
    "text": '{"success": true}'
}

MOCK_HTTP_ERROR = {
    "status_code": 400,
    "json": lambda: {"error": "Bad Request"},
    "text": '{"error": "Bad Request"}'
}

MOCK_SUPABASE_API_RESPONSE = {
    "status_code": 200,
    "json": lambda: {
        "id": "doc_1234567890",
        "title": "Test Document",
        "content": "Test content"
    },
    "text": '{"id": "doc_1234567890", "title": "Test Document", "content": "Test content"}'
}
```

## Mock Factories

### User Factory
```python
# tests/factories/user_factory.py
"""Factory for creating mock user data."""

import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional

class UserFactory:
    """Factory for creating mock user data."""
    
    @staticmethod
    def create(**overrides) -> Dict[str, Any]:
        """Create a mock user with optional overrides."""
        defaults = {
            "id": str(uuid.uuid4()),
            "username": f"testuser_{uuid.uuid4().hex[:8]}",
            "email": f"test_{uuid.uuid4().hex[:8]}@example.com",
            "password": "testpassword123",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        defaults.update(overrides)
        return defaults
    
    @staticmethod
    def create_batch(count: int, **overrides) -> list:
        """Create a batch of mock users."""
        return [UserFactory.create(**overrides) for _ in range(count)]
    
    @staticmethod
    def create_admin(**overrides) -> Dict[str, Any]:
        """Create a mock admin user."""
        admin_data = {
            "username": "admin",
            "email": "admin@example.com",
            "is_admin": True
        }
        admin_data.update(overrides)
        return UserFactory.create(**admin_data)
```

### Document Factory
```python
# tests/factories/document_factory.py
"""Factory for creating mock document data."""

import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional

class DocumentFactory:
    """Factory for creating mock document data."""
    
    @staticmethod
    def create(**overrides) -> Dict[str, Any]:
        """Create a mock document with optional overrides."""
        defaults = {
            "id": str(uuid.uuid4()),
            "title": f"Test Document {uuid.uuid4().hex[:8]}",
            "content": "This is a test document with sample content for processing and analysis.",
            "author_id": str(uuid.uuid4()),
            "status": "published",
            "tags": ["test", "document", "sample"],
            "created_at": datetime.now(timezone.utc).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        defaults.update(overrides)
        return defaults
    
    @staticmethod
    def create_batch(count: int, **overrides) -> list:
        """Create a batch of mock documents."""
        return [DocumentFactory.create(**overrides) for _ in range(count)]
    
    @staticmethod
    def create_draft(**overrides) -> Dict[str, Any]:
        """Create a mock draft document."""
        draft_data = {
            "status": "draft",
            "title": f"Draft Document {uuid.uuid4().hex[:8]}"
        }
        draft_data.update(overrides)
        return DocumentFactory.create(**draft_data)
    
    @staticmethod
    def create_with_chunks(chunk_count: int = 3, **overrides) -> tuple:
        """Create a document with associated chunks."""
        document = DocumentFactory.create(**overrides)
        
        chunks = []
        for i in range(chunk_count):
            chunk = {
                "id": str(uuid.uuid4()),
                "document_id": document["id"],
                "content": f"This is chunk {i+1} of the document.",
                "position": i,
                "created_at": document["created_at"]
            }
            chunks.append(chunk)
        
        return document, chunks
```

## Mock Data Providers

### Random Data Generator
```python
# tests/providers/random_data.py
"""Provider for generating random test data."""

import random
import string
import uuid
from datetime import datetime, timedelta
from typing import List, Dict, Any

class RandomDataProvider:
    """Provider for generating random test data."""
    
    @staticmethod
    def random_string(length: int = 10) -> str:
        """Generate a random string."""
        return ''.join(random.choices(string.ascii_letters + string.digits, k=length))
    
    @staticmethod
    def random_email() -> str:
        """Generate a random email."""
        return f"test_{RandomDataProvider.random_string(8)}@example.com"
    
    @staticmethod
    def random_uuid() -> str:
        """Generate a random UUID."""
        return str(uuid.uuid4())
    
    @staticmethod
    def random_datetime(days_back: int = 30) -> str:
        """Generate a random datetime within the last N days."""
        now = datetime.now()
        random_time = now - timedelta(days=random.randint(0, days_back))
        return random_time.isoformat()
    
    @staticmethod
    def random_tags(count: int = 3) -> List[str]:
        """Generate random tags."""
        tag_prefixes = ["test", "sample", "demo", "mock", "fake", "dummy"]
        tag_suffixes = ["data", "content", "item", "record", "entry", "entity"]
        
        tags = []
        for _ in range(count):
            prefix = random.choice(tag_prefixes)
            suffix = random.choice(tag_suffixes)
            tags.append(f"{prefix}_{suffix}")
        
        return list(set(tags))  # Remove duplicates
```

### Test Data Loader
```python
# tests/providers/data_loader.py
"""Provider for loading test data from various sources."""

import json
import csv
from pathlib import Path
from typing import List, Dict, Any

class TestDataLoader:
    """Provider for loading test data from files."""
    
    @staticmethod
    def load_json_data(file_path: str) -> Dict[str, Any]:
        """Load test data from JSON file."""
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Test data file not found: {file_path}")
        
        with open(path, 'r') as f:
            return json.load(f)
    
    @staticmethod
    def load_csv_data(file_path: str) -> List[Dict[str, Any]]:
        """Load test data from CSV file."""
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Test data file not found: {file_path}")
        
        data = []
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                data.append(row)
        
        return data
    
    @staticmethod
    def load_yaml_data(file_path: str) -> Dict[str, Any]:
        """Load test data from YAML file."""
        try:
            import yaml
            path = Path(file_path)
            if not path.exists():
                raise FileNotFoundError(f"Test data file not found: {file_path}")
            
            with open(path, 'r') as f:
                return yaml.safe_load(f)
        except ImportError:
            raise ImportError("PyYAML is required to load YAML test data")
```

## Mock Data Validation

### Data Validator
```python
# tests/validation/data_validator.py
"""Validator for mock test data."""

from typing import Dict, Any, List

class MockDataValidator:
    """Validator for mock test data."""
    
    @staticmethod
    def validate_user(user: Dict[str, Any]) -> List[str]:
        """Validate user mock data."""
        errors = []
        
        # Required fields
        required_fields = ["id", "username", "email"]
        for field in required_fields:
            if field not in user:
                errors.append(f"Missing required field: {field}")
        
        # Field validations
        if "email" in user and "@" not in user["email"]:
            errors.append("Invalid email format")
        
        if "username" in user and len(user["username"]) < 3:
            errors.append("Username must be at least 3 characters")
        
        return errors
    
    @staticmethod
    def validate_document(document: Dict[str, Any]) -> List[str]:
        """Validate document mock data."""
        errors = []
        
        # Required fields
        required_fields = ["id", "title", "content", "author_id"]
        for field in required_fields:
            if field not in document:
                errors.append(f"Missing required field: {field}")
        
        # Field validations
        if "title" in document and len(document["title"]) < 1:
            errors.append("Title cannot be empty")
        
        if "content" in document and len(document["content"]) < 1:
            errors.append("Content cannot be empty")
        
        return errors
    
    @staticmethod
    def validate_all(data_list: List[Dict[str, Any]], data_type: str = "user") -> Dict[str, List[str]]:
        """Validate a list of mock data."""
        validator_map = {
            "user": MockDataValidator.validate_user,
            "document": MockDataValidator.validate_document
        }
        
        validator = validator_map.get(data_type, MockDataValidator.validate_user)
        results = {}
        
        for i, data in enumerate(data_list):
            errors = validator(data)
            if errors:
                results[f"item_{i}"] = errors
        
        return results
```

## Usage Examples

### Using Mock Data in Tests
```python
# tests/unit/test_user_service.py
"""Tests for user service using mock data."""

import pytest
from tests.mocks.users import MOCK_USER, MOCK_USERS
from tests.factories.user_factory import UserFactory
from tests.validation.data_validator import MockDataValidator

def test_create_user_with_mock_data():
    """Test creating user with mock data."""
    # Validate mock data first
    errors = MockDataValidator.validate_user(MOCK_USER)
    assert len(errors) == 0, f"Mock data validation failed: {errors}"
    
    # Test user creation
    result = user_service.create_user(MOCK_USER)
    assert result is not None
    assert result["id"] == MOCK_USER["id"]

def test_create_user_with_factory():
    """Test creating user with factory-generated data."""
    # Generate mock user
    mock_user = UserFactory.create(username="factory_test_user")
    
    # Validate generated data
    errors = MockDataValidator.validate_user(mock_user)
    assert len(errors) == 0, f"Generated data validation failed: {errors}"
    
    # Test user creation
    result = user_service.create_user(mock_user)
    assert result is not None
    assert result["username"] == "factory_test_user"

def test_list_users_with_batch_data():
    """Test listing users with batch mock data."""
    # Validate batch mock data
    validation_results = MockDataValidator.validate_all(MOCK_USERS, "user")
    assert len(validation_results) == 0, f"Batch data validation failed: {validation_results}"
    
    # Test user listing
    for mock_user in MOCK_USERS:
        user_service.create_user(mock_user)
    
    result = user_service.list_users()
    assert len(result) >= len(MOCK_USERS)
```

## Best Practices

### Mock Data Design
1. **Realistic but simplified**: Mock data should resemble real data but be simplified for testing
2. **Consistent structure**: Maintain consistent data structures across mocks
3. **Easy validation**: Design mock data to be easily validated
4. **Flexible generation**: Provide ways to customize mock data for specific test needs

### Mock Data Maintenance
1. **Version control**: Keep mock data in version control
2. **Regular updates**: Update mock data when data structures change
3. **Documentation**: Document mock data structures and usage
4. **Validation**: Regularly validate mock data integrity

### Performance Considerations
1. **Efficient generation**: Optimize mock data generation for speed
2. **Caching**: Cache frequently used mock data
3. **Batch operations**: Support batch generation of mock data
4. **Memory management**: Clean up large mock data sets after use

### Security Practices
1. **No real data**: Never use real production data in mocks
2. **Secure credentials**: Use secure, non-production credentials in mock data
3. **Data anonymization**: Anonymize any derived test data
4. **Regular rotation**: Rotate mock credentials regularly