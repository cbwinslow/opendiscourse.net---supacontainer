"""
Provider for generating random test data.
"""

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