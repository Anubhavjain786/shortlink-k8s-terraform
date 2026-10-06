"""shortlink: a small URL shortener API backed by Redis."""

import secrets
import string
import time
from contextlib import asynccontextmanager

import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import RedirectResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, HttpUrl

from .config import settings

ALPHABET = string.ascii_letters + string.digits

REQUESTS = Counter("shortlink_http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("shortlink_http_request_duration_seconds", "HTTP request latency", ["route"])
LINKS_CREATED = Counter("shortlink_links_created_total", "Short links created")
REDIRECTS = Counter("shortlink_redirects_total", "Redirects served")


class LinkIn(BaseModel):
    url: HttpUrl


class LinkOut(BaseModel):
    code: str
    url: str
    short_url: str


class StatsOut(BaseModel):
    code: str
    url: str
    hits: int


def new_code(length: int) -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(length))


def create_app(redis_client: redis.Redis | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.redis = redis_client or redis.from_url(settings.redis_url, decode_responses=True)
        yield
        await app.state.redis.aclose()

    app = FastAPI(title="shortlink", version=settings.version, lifespan=lifespan)

    @app.middleware("http")
    async def record_metrics(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        route = request.scope.get("route")
        route_path = getattr(route, "path", "unmatched")
        REQUESTS.labels(request.method, route_path, response.status_code).inc()
        LATENCY.labels(route_path).observe(time.perf_counter() - start)
        return response

    @app.get("/healthz", include_in_schema=False)
    async def healthz():
        """Liveness: the process is up."""
        return {"status": "ok", "version": settings.version}

    @app.get("/readyz", include_in_schema=False)
    async def readyz(request: Request):
        """Readiness: the process can reach Redis."""
        try:
            await request.app.state.redis.ping()
        except Exception as exc:  # any failure means not ready
            raise HTTPException(status_code=503, detail="redis unavailable") from exc
        return {"status": "ready"}

    @app.get("/metrics", include_in_schema=False)
    async def metrics():
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.post("/links", response_model=LinkOut, status_code=201)
    async def create_link(body: LinkIn, request: Request):
        r = request.app.state.redis
        url = str(body.url)
        for _ in range(5):  # retry on the (unlikely) code collision
            code = new_code(settings.code_length)
            if await r.set(f"link:{code}", url, nx=True):
                LINKS_CREATED.inc()
                base = settings.base_url.rstrip("/") or str(request.base_url).rstrip("/")
                return LinkOut(code=code, url=url, short_url=f"{base}/{code}")
        raise HTTPException(status_code=503, detail="could not allocate a code")

    @app.get("/links/{code}/stats", response_model=StatsOut)
    async def link_stats(code: str, request: Request):
        r = request.app.state.redis
        url = await r.get(f"link:{code}")
        if url is None:
            raise HTTPException(status_code=404, detail="link not found")
        hits = int(await r.get(f"hits:{code}") or 0)
        return StatsOut(code=code, url=url, hits=hits)

    @app.get("/{code}", include_in_schema=False)
    async def follow(code: str, request: Request):
        r = request.app.state.redis
        url = await r.get(f"link:{code}")
        if url is None:
            raise HTTPException(status_code=404, detail="link not found")
        await r.incr(f"hits:{code}")
        REDIRECTS.inc()
        return RedirectResponse(url, status_code=307)

    return app


app = create_app()
