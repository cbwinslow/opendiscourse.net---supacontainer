"""
Factory for creating mock document data.
"""

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