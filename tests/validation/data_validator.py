"""
Validator for mock test data.
"""

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