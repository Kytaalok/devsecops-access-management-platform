from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Task Manager API"
    app_env: str = "dev"
    database_url: str = "sqlite:///./task_manager.db"
    auth_enabled: bool = False
    jwt_algorithm: str = "RS256"
    keycloak_issuer: str = "http://localhost:8080/realms/devsecops"
    keycloak_audience: str | None = None
    keycloak_client_id: str = "task-manager-api"
    keycloak_jwks_url: str | None = None
    cors_allow_origins: str = "*"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)


settings = Settings()
