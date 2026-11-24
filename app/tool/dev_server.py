"""Development server for the Flutter web app: the real API and app/build/web on one
origin, as nginx and Traefik do in production (the API grants no CORS, and the session
cookie is SameSite=Strict). Plain HTTP, so the cookie is sent without the Secure flag.

    app/tool/build.sh web
    CAPSA_DATABASE_URL=sqlite:///dev.sqlite CAPSA_PROFILE_DIR=profiles/demo \\
        uv run python app/tool/dev_server.py [--port 8092]

Android emulators reach it at http://10.0.2.2:<port> (debug builds allow plain HTTP).
"""

import argparse
import os
from pathlib import Path

import uvicorn
from capsa.app import create_app
from fastapi.staticfiles import StaticFiles

WEB = Path(__file__).resolve().parent.parent / "build" / "web"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8092)
    args = parser.parse_args()
    os.environ.setdefault("CAPSA_COOKIE_SECURE", "false")
    app = create_app()
    # Mounted after the API routes, so /api/... still goes to the API.
    app.mount("/", StaticFiles(directory=WEB, html=True, check_dir=False), name="web")
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
