"""
Tests for documentation files.
"""

import pytest
import os
from pathlib import Path

class TestDocumentation:
    """Test documentation files."""
    
    def test_readme_exists(self):
        """Test that README.md exists."""
        readme = Path("README.md")
        assert readme.exists(), "README.md not found"
    
    def test_deployment_guide_exists(self):
        """Test that DEPLOYMENT_GUIDE.md exists."""
        guide = Path("DEPLOYMENT_GUIDE.md")
        assert guide.exists(), "DEPLOYMENT_GUIDE.md not found"
    
    def test_tasks_md_exists(self):
        """Test that TASKS.md exists."""
        tasks = Path("TASKS.md")
        assert tasks.exists(), "TASKS.md not found"
    
    def test_agents_md_exists(self):
        """Test that AGENTS.md exists."""
        agents = Path("AGENTS.md")
        assert agents.exists(), "AGENTS.md not found"
    
    def test_qwen_md_exists(self):
        """Test that QWEN.md exists."""
        qwen = Path("QWEN.md")
        assert qwen.exists(), "QWEN.md not found"
    
    def test_test_readme_exists(self):
        """Test that tests/README.md exists."""
        test_readme = Path("tests/README.md")
        assert test_readme.exists(), "tests/README.md not found"
    
    def test_test_procedures_exist(self):
        """Test that test procedures documentation exists."""
        procedures = Path("tests/TESTING_PROCEDURES.md")
        assert procedures.exists(), "tests/TESTING_PROCEDURES.md not found"
    
    def test_test_coverage_doc_exists(self):
        """Test that test coverage documentation exists."""
        coverage_doc = Path("tests/COVERAGE.md")
        assert coverage_doc.exists(), "tests/COVERAGE.md not found"
    
    def test_environment_setup_doc_exists(self):
        """Test that environment setup documentation exists."""
        env_setup = Path("tests/ENVIRONMENT_SETUP.md")
        assert env_setup.exists(), "tests/ENVIRONMENT_SETUP.md not found"
    
    def test_ci_doc_exists(self):
        """Test that CI documentation exists."""
        ci_doc = Path("tests/CONTINUOUS_INTEGRATION.md")
        assert ci_doc.exists(), "tests/CONTINUOUS_INTEGRATION.md not found"
    
    def test_data_management_doc_exists(self):
        """Test that data management documentation exists."""
        data_doc = Path("tests/DATA_MANAGEMENT.md")
        assert data_doc.exists(), "tests/DATA_MANAGEMENT.md not found"
    
    def test_fixtures_doc_exists(self):
        """Test that fixtures documentation exists."""
        fixtures_doc = Path("tests/FIXTURES_AND_CONFIGURATION.md")
        assert fixtures_doc.exists(), "tests/FIXTURES_AND_CONFIGURATION.md not found"
    
    def test_mock_data_doc_exists(self):
        """Test that mock data documentation exists."""
        mock_doc = Path("tests/MOCK_DATA.md")
        assert mock_doc.exists(), "tests/MOCK_DATA.md not found"
    
    def test_documentation_has_content(self):
        """Test that documentation files have content."""
        docs = [
            "README.md",
            "DEPLOYMENT_GUIDE.md",
            "TASKS.md",
            "AGENTS.md",
            "QWEN.md",
            "tests/README.md",
            "tests/TESTING_PROCEDURES.md",
            "tests/COVERAGE.md"
        ]
        
        for doc in docs:
            doc_path = Path(doc)
            assert doc_path.exists(), f"{doc} not found"
            
            with open(doc_path, 'r') as f:
                content = f.read()
            
            assert len(content.strip()) > 0, f"{doc} is empty"
            assert "#" in content, f"{doc} doesn't appear to be markdown"
    
    def test_documentation_links_work(self):
        """Test that documentation links are valid."""
        docs = [
            "README.md",
            "DEPLOYMENT_GUIDE.md",
            "TASKS.md",
            "AGENTS.md"
        ]
        
        for doc in docs:
            doc_path = Path(doc)
            if not doc_path.exists():
                continue
                
            with open(doc_path, 'r') as f:
                content = f.read()
            
            # Check for relative links to other docs
            import re
            links = re.findall(r'\[([^\]]+)\]\(([^)]+)\)', content)
            
            for link_text, link_url in links:
                # Skip external links
                if link_url.startswith(('http://', 'https://', 'mailto:')):
                    continue
                
                # Check relative file links
                if link_url.endswith('.md'):
                    linked_file = doc_path.parent / link_url
                    assert linked_file.exists(), f"Broken link in {doc}: {link_url}"