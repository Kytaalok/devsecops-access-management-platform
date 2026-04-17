from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser, get_current_user
from app.deps import get_db
from app.schemas import TaskCreate, TaskOut, TaskUpdate
from app.services.task_service import (
    create_task_for_user,
    delete_task_for_user,
    ensure_can_read_task,
    get_task_or_404,
    list_tasks_for_user,
    update_task_for_user,
)

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskOut])
def list_tasks(
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[TaskOut]:
    return list_tasks_for_user(db, current_user)


@router.post("", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def create_task(
    payload: TaskCreate,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TaskOut:
    return create_task_for_user(db, current_user, payload)


@router.get("/{task_id}", response_model=TaskOut)
def get_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TaskOut:
    task = get_task_or_404(db, task_id)
    ensure_can_read_task(current_user, task)
    return task


@router.put("/{task_id}", response_model=TaskOut)
def update_task(
    task_id: int,
    payload: TaskUpdate,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TaskOut:
    task = get_task_or_404(db, task_id)
    return update_task_for_user(db, current_user, task, payload)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    task = get_task_or_404(db, task_id)
    delete_task_for_user(db, current_user, task)
