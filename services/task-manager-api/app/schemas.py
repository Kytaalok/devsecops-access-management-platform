from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


TaskStatus = Literal["new", "in_progress", "done", "archived"]
UserRole = Literal["admin", "developer", "viewer"]


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    status: TaskStatus = "new"


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    status: TaskStatus | None = None


class TaskOut(BaseModel):
    id: int
    title: str
    description: str | None
    status: TaskStatus
    owner_id: str
    owner_username: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class CurrentUserOut(BaseModel):
    id: str
    username: str
    email: str | None = None
    role: UserRole
