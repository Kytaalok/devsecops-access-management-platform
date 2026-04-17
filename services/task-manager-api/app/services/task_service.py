from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser, ensure_any_role
from app.models import Task
from app.schemas import TaskCreate, TaskUpdate


def list_tasks_for_user(db: Session, user: CurrentUser) -> list[Task]:
    if user.is_admin or user.is_viewer:
        return db.query(Task).order_by(Task.id.desc()).all()

    return db.query(Task).filter(Task.owner_id == user.user_id).order_by(Task.id.desc()).all()


def create_task_for_user(db: Session, user: CurrentUser, payload: TaskCreate) -> Task:
    ensure_any_role(user, {"admin", "developer"})

    task = Task(
        title=payload.title,
        description=payload.description,
        status=payload.status,
        owner_id=user.user_id,
        owner_username=user.username,
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def get_task_or_404(db: Session, task_id: int) -> Task:
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return task


def ensure_can_read_task(user: CurrentUser, task: Task) -> None:
    if user.is_admin or user.is_viewer:
        return
    if user.is_developer and task.owner_id == user.user_id:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Read access denied")


def ensure_can_modify_task(user: CurrentUser, task: Task) -> None:
    if user.is_admin:
        return
    if user.is_developer and task.owner_id == user.user_id:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Write access denied")


def update_task_for_user(db: Session, user: CurrentUser, task: Task, payload: TaskUpdate) -> Task:
    ensure_can_modify_task(user, task)

    if payload.title is not None:
        task.title = payload.title
    if payload.description is not None:
        task.description = payload.description
    if payload.status is not None:
        task.status = payload.status

    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def delete_task_for_user(db: Session, user: CurrentUser, task: Task) -> None:
    ensure_can_modify_task(user, task)
    db.delete(task)
    db.commit()

