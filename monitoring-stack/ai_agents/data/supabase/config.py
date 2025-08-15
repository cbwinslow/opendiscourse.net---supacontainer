"""Supabase client configuration and initialization."""
import os
from typing import Optional
from dotenv import load_dotenv
from supabase import create_client, Client as SupabaseClient

# Load environment variables from .env file if it exists
load_dotenv()

class SupabaseConfig:
    """Configuration for Supabase client."""
    
    def __init__(
        self,
        url: Optional[str] = None,
        key: Optional[str] = None,
        schema: str = "public"
    ):
        """Initialize Supabase configuration.
        
        Args:
            url: Supabase project URL. If not provided, will try to get from environment.
            key: Supabase service role or anon key. If not provided, will try to get from environment.
            schema: Database schema to use (default: public)
        """
        self.url = url or os.getenv("SUPABASE_URL")
        self.key = key or os.getenv("SUPABASE_KEY")
        self.schema = schema
        
        if not self.url or not self.key:
            raise ValueError(
                "Supabase URL and key must be provided either through constructor "
                "arguments or environment variables (SUPABASE_URL, SUPABASE_KEY)"
            )

def get_supabase_client(config: Optional[SupabaseConfig] = None) -> SupabaseClient:
    """Create and return a Supabase client instance.
    
    Args:
        config: Optional configuration. If not provided, will create from environment.
        
    Returns:
        Initialized Supabase client.
    """
    if config is None:
        config = SupabaseConfig()
    
    return create_client(config.url, config.key)
