"""
Mock document data for testing.
"""

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