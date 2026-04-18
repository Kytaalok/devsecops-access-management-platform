from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.db import Base, engine
from app.routers.health import router as health_router
from app.routers.tasks import router as tasks_router
from app.routers.users import router as users_router

app = FastAPI(title=settings.app_name)

if settings.cors_allow_origins.strip() == "*":
    origins = ["*"]
else:
    origins = [origin.strip() for origin in settings.cors_allow_origins.split(",") if origin.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup() -> None:
    Base.metadata.create_all(bind=engine)


app.include_router(health_router)
app.include_router(users_router)
app.include_router(tasks_router)
