"""
Mock user data for testing.
"""

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