""
Integration tests for OpenDiscourse automation services.
"""
import os
import pytest
import requests
from minio import Minio
from minio.error import S3Error

class TestN8NIntegration:
    """Integration tests for n8n service."""
    
    @pytest.fixture(autouse=True)
    def setup(self, n8n_service):
        self.base_url = n8n_service
        self.auth = (
            os.getenv("N8N_USER", "admin"),
            os.getenv("N8N_PASSWORD", "admin")
        )
        self.headers = {"Content-Type": "application/json"}
    
    def test_n8n_health_check(self):
        """Test n8n health check endpoint."""
        response = requests.get(
            f"{self.base_url}/healthz",
            auth=self.auth,
            timeout=10
        )
        assert response.status_code == 200
        assert response.json()["status"] == "ok"
    
    def test_n8n_workflow_creation(self):
        """Test creating a simple workflow in n8n."""
        workflow = {
            "name": "Test Workflow",
            "nodes": [
                {
                    "name": "Start",
                    "type": "n8n-nodes-base.start",
                    "typeVersion": 1,
                    "position": [250, 300]
                }
            ],
            "connections": {}
        }
        
        response = requests.post(
            f"{self.base_url}/rest/workflows",
            json=workflow,
            auth=self.auth,
            headers=self.headers,
            timeout=10
        )
        
        assert response.status_code == 200
        assert "id" in response.json()


class TestBackupIntegration:
    """Integration tests for backup service."""
    
    @pytest.fixture(autouse=True)
    def setup(self, minio_service):
        self.client = Minio(
            minio_service.replace("http://", ""),
            access_key=os.getenv("MINIO_ACCESS_KEY", "minioadmin"),
            secret_key=os.getenv("MINIO_SECRET_KEY", "minioadmin"),
            secure=False
        )
        self.bucket_name = os.getenv("BACKUP_BUCKET", "opendiscourse-backups")
    
    def test_minio_connection(self):
        """Test connection to MinIO service."""
        assert self.client.bucket_exists(self.bucket_name) or \
               self.client.make_bucket(self.bucket_name)
    
    def test_backup_upload(self, tmp_path):
        """Test uploading a backup file to MinIO."""
        # Create a test file
        test_file = tmp_path / "test_backup.tar.gz"
        test_file.write_text("test backup content")
        
        # Upload the file
        self.client.fput_object(
            self.bucket_name,
            "test_backup.tar.gz",
            str(test_file)
        )
        
        # Verify the file exists
        objects = list(self.client.list_objects(self.bucket_name))
        assert any(obj.object_name == "test_backup.tar.gz" for obj in objects)
        
        # Cleanup
        self.client.remove_object(self.bucket_name, "test_backup.tar.gz")
