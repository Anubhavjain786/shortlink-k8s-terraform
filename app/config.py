from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration, read from environment variables."""

    model_config = SettingsConfigDict(env_prefix="SHORTLINK_")

    redis_url: str = "redis://localhost:6379/0"
    base_url: str = ""  # public base URL for short links; falls back to the request URL
    code_length: int = 7
    version: str = "dev"


settings = Settings()
