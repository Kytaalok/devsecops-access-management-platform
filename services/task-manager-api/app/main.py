from fastapi import FastAPI

from app.config import settings
from app.db import Base, engine
from app.routers.health import router as health_router
from app.routers.tasks import router as tasks_router
from app.routers.users import router as users_router

app = FastAPI(title=settings.app_name)


@app.on_event("startup")
def startup() -> None:
    Base.metadata.create_all(bind=engine)


app.include_router(health_router)
app.include_router(users_router)
app.include_router(tasks_router)
