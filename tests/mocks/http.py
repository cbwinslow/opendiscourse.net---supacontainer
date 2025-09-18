"""
Mock HTTP responses for testing.
"""

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