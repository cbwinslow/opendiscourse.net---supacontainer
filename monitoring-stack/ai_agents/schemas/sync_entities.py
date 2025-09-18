from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class ExternalTask(BaseModel):
    id: Optional[int] = None
    type: str  # 'jira', 'bitbucket', 'linear'
    external_id: str
    synced_at: Optional[datetime] = None

class GitHubIssue(BaseModel):
    id: Optional[int] = None
    repo: str
    title: str
    status: str
    syncs_to: List[ExternalTask] = []

# Additional models can be extended here for relationships