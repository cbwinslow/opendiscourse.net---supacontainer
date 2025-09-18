from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import yaml  # For workflow YAML handling

from .sync_entities import GitHubIssue

class Diff(BaseModel):
    id: Optional[int] = None
    commit_id: str
    changes: str  # Raw diff content
    file_changes: List[str] = []  # List of affected files
    created_at: Optional[datetime] = None

class Commit(BaseModel):
    id: str
    repo: str
    message: str
    diff: Diff
    analyzed_by: List['Workflow'] = []  # Relationship to generated workflows
    created_at: Optional[datetime] = None

class Workflow(BaseModel):
    id: Optional[int] = None
    commit_id: str
    yaml_content: str  # YAML string for GitHub workflow
    generated_issues: List[GitHubIssue] = []  # Issues created from analysis
    created_at: Optional[datetime] = None

    def validate_yaml(self) -> bool:
        """Basic validation for YAML workflow content"""
        try:
            yaml.safe_load(self.yaml_content)
            return True
        except yaml.YAMLError:
            return False

class PullRequest(BaseModel):
    id: Optional[int] = None
    title: str
    body: str
    diff_id: str  # Reference to generating diff
    repo: str
    created_at: Optional[datetime] = None