#!/usr/bin/env python3
"""
Supabase Monitoring Script

This script monitors the health and performance of a Supabase instance.
It checks database connections, storage usage, and API endpoints.
"""
import os
import time
import json
import psycopg2
import requests
from datetime import datetime
from typing import Dict, Any, Optional
import logging
from dataclasses import dataclass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('supabase_monitor.log')
    ]
)

logger = logging.getLogger(__name__)

@dataclass
class SupabaseConfig:
    """Configuration for Supabase connection."""
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "postgres"
    db_user: str = "postgres"
    db_password: str = ""
    supabase_url: str = "http://localhost:8000"
    anon_key: str = ""
    service_role_key: str = ""

    @classmethod
    def from_env(cls) -> 'SupabaseConfig':
        """Load configuration from environment variables."""
        return cls(
            db_host=os.getenv("DB_HOST", "localhost"),
            db_port=int(os.getenv("DB_PORT", "5432")),
            db_name=os.getenv("POSTGRES_DB", "postgres"),
            db_user=os.getenv("POSTGRES_USER", "postgres"),
            db_password=os.getenv("POSTGRES_PASSWORD", ""),
            supabase_url=os.getenv("SUPABASE_URL", "http://localhost:8000"),
            anon_key=os.getenv("ANON_KEY", ""),
            service_role_key=os.getenv("SERVICE_ROLE_KEY", "")
        )

class SupabaseMonitor:
    """Monitor Supabase instance health and performance."""
    
    def __init__(self, config: SupabaseConfig):
        """Initialize the monitor with configuration."""
        self.config = config
        self.headers = {
            "apikey": config.anon_key,
            "Authorization": f"Bearer {config.anon_key}",
            "Content-Type": "application/json"
        }
    
    def check_database_connection(self) -> Dict[str, Any]:
        """Check if we can connect to the database."""
        try:
            start_time = time.time()
            conn = psycopg2.connect(
                host=self.config.db_host,
                port=self.config.db_port,
                dbname=self.config.db_name,
                user=self.config.db_user,
                password=self.config.db_password
            )
            conn.close()
            return {
                "status": "healthy",
                "latency_ms": (time.time() - start_time) * 1000
            }
        except Exception as e:
            logger.error(f"Database connection failed: {str(e)}")
            return {
                "status": "unhealthy",
                "error": str(e)
            }
    
    def check_rest_api(self) -> Dict[str, Any]:
        """Check if the REST API is responding."""
        try:
            start_time = time.time()
            response = requests.get(
                f"{self.config.supabase_url}/rest/v1/",
                headers={"apikey": self.config.anon_key}
            )
            response.raise_for_status()
            return {
                "status": "healthy",
                "status_code": response.status_code,
                "latency_ms": (time.time() - start_time) * 1000
            }
        except Exception as e:
            logger.error(f"REST API check failed: {str(e)}")
            return {
                "status": "unhealthy",
                "error": str(e)
            }
    
    def check_auth_api(self) -> Dict[str, Any]:
        """Check if the Auth API is responding."""
        try:
            start_time = time.time()
            response = requests.get(
                f"{self.config.supabase_url}/auth/v1/settings",
                headers={"apikey": self.config.anon_key}
            )
            response.raise_for_status()
            return {
                "status": "healthy",
                "status_code": response.status_code,
                "latency_ms": (time.time() - start_time) * 1000
            }
        except Exception as e:
            logger.error(f"Auth API check failed: {str(e)}")
            return {
                "status": "unhealthy",
                "error": str(e)
            }
    
    def get_database_metrics(self) -> Dict[str, Any]:
        """Get database performance metrics."""
        metrics = {}
        try:
            conn = psycopg2.connect(
                host=self.config.db_host,
                port=self.config.db_port,
                dbname=self.config.db_name,
                user=self.config.db_user,
                password=self.config.db_password
            )
            cursor = conn.cursor()
            
            # Get database size
            cursor.execute("""
                SELECT pg_size_pretty(pg_database_size(current_database()))
            """)
            metrics["database_size"] = cursor.fetchone()[0]
            
            # Get active connections
            cursor.execute("""
                SELECT COUNT(*) FROM pg_stat_activity 
                WHERE datname = current_database()
            """)
            metrics["active_connections"] = cursor.fetchone()[0]
            
            # Get table sizes
            cursor.execute("""
                SELECT 
                    table_schema,
                    table_name, 
                    pg_size_pretty(pg_total_relation_size('"' || table_schema || '"."' || table_name || '"')) as size
                FROM information_schema.tables
                WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
                ORDER BY pg_total_relation_size('"' || table_schema || '"."' || table_name || '"') DESC;
            """)
            metrics["table_sizes"] = [
                {"schema": row[0], "table": row[1], "size": row[2]} 
                for row in cursor.fetchall()
            ]
            
            # Get long running queries
            cursor.execute("""
                SELECT 
                    pid, 
                    now() - query_start as duration, 
                    query 
                FROM pg_stat_activity 
                WHERE now() - query_start > interval '5 seconds' 
                AND state != 'idle' 
                ORDER BY duration DESC;
            """)
            metrics["long_running_queries"] = [
                {"pid": row[0], "duration": str(row[1]), "query": row[2]}
                for row in cursor.fetchall()
            ]
            
            conn.close()
            metrics["status"] = "success"
            
        except Exception as e:
            logger.error(f"Failed to get database metrics: {str(e)}")
            metrics["status"] = "error"
            metrics["error"] = str(e)
            
        return metrics
    
    def get_storage_metrics(self) -> Dict[str, Any]:
        """Get storage usage metrics."""
        metrics = {"buckets": []}
        try:
            # List all buckets
            response = requests.get(
                f"{self.config.supabase_url}/storage/v1/bucket",
                headers={"Authorization": f"Bearer {self.config.service_role_key}"}
            )
            response.raise_for_status()
            
            for bucket in response.json():
                # Get bucket usage
                bucket_name = bucket["name"]
                usage_response = requests.get(
                    f"{self.config.supabase_url}/storage/v1/bucket/{bucket_name}/usage",
                    headers={"Authorization": f"Bearer {self.config.service_role_key}"}
                )
                
                if usage_response.status_code == 200:
                    usage = usage_response.json()
                    metrics["buckets"].append({
                        "name": bucket_name,
                        "objects": usage.get("objects", 0),
                        "size": usage.get("size", 0),
                        "size_formatted": self._format_bytes(usage.get("size", 0))
                    })
            
            metrics["status"] = "success"
            
        except Exception as e:
            logger.error(f"Failed to get storage metrics: {str(e)}")
            metrics["status"] = "error"
            metrics["error"] = str(e)
            
        return metrics
    
    def _format_bytes(self, size_bytes: int) -> str:
        """Format bytes to a human-readable string."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.2f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.2f} PB"
    
    def run_health_check(self) -> Dict[str, Any]:
        """Run all health checks and return results."""
        logger.info("Starting Supabase health check...")
        
        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "services": {
                "database": self.check_database_connection(),
                "rest_api": self.check_rest_api(),
                "auth_api": self.check_auth_api()
            },
            "metrics": {
                "database": self.get_database_metrics(),
                "storage": self.get_storage_metrics()
            }
        }
        
        # Log overall status
        all_healthy = all(
            service["status"] == "healthy" 
            for service in results["services"].values()
        )
        
        results["status"] = "healthy" if all_healthy else "degraded"
        logger.info(f"Health check completed. Status: {results['status']}")
        
        return results

if __name__ == "__main__":
    # Load configuration
    config = SupabaseConfig.from_env()
    
    # Initialize monitor
    monitor = SupabaseMonitor(config)
    
    # Run health check
    results = monitor.run_health_check()
    
    # Print results
    print(json.dumps(results, indent=2))
