"""
Factory for creating mock user data.
"""

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