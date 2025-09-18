"""
Mock authentication data for testing.
"""

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