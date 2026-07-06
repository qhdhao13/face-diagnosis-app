#!/usr/bin/env python3
"""
二十五色部云端分析内部 API（由 Node 体验服反向代理）
数据与图片全部落盘到 REGION25_DATA_DIR
"""
from __future__ import annotations

import base64
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Dict
from urllib.parse import urlparse

ROOT = Path(__file__).parent
DATA_DIR = Path(os.environ.get("REGION25_DATA_DIR", ROOT.parent / "experience-server" / "data" / "sessions"))
PORT = int(os.environ.get("REGION25_API_PORT", "8788"))


def _json_response(handler: BaseHTTPRequestHandler, code: int, payload: Dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Region25Handler(BaseHTTPRequestHandler):
    """极简 HTTP 处理器，避免额外依赖 Flask"""

    def log_message(self, fmt: str, *args) -> None:
        print(f"[region25-api] {self.address_string()} {fmt % args}")

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            _json_response(self, 200, {"ok": True, "service": "region25-api"})
            return
        _json_response(self, 404, {"ok": False, "message": "not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/internal/analyze":
            _json_response(self, 404, {"ok": False, "message": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            body = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            _json_response(self, 400, {"ok": False, "message": "invalid json"})
            return

        session_id = str(body.get("sessionId", "")).strip()
        phone = str(body.get("phone", "")).strip()
        profile_gender = str(body.get("profileGender", "")).strip()
        image_b64 = body.get("imageBase64", "")

        if not session_id or not image_b64:
            _json_response(self, 400, {"ok": False, "message": "缺少 sessionId 或 imageBase64"})
            return

        try:
            image_bytes = base64.b64decode(image_b64)
        except Exception:
            _json_response(self, 400, {"ok": False, "message": "imageBase64 解码失败"})
            return

        session_dir = DATA_DIR / session_id
        if session_dir.exists():
            _json_response(self, 409, {"ok": False, "message": "sessionId 已存在"})
            return

        try:
            from pipeline import run_pipeline_from_bytes

            result = run_pipeline_from_bytes(
                image_bytes,
                session_dir=session_dir,
                phone=phone,
                profile_gender=profile_gender,
            )
        except Exception as exc:
            print(f"[region25-api] analyze failed: {exc}")
            _json_response(self, 422, {"ok": False, "message": str(exc)})
            return

        color_report = result["colorReport"]
        _json_response(
            self,
            200,
            {
                "ok": True,
                "sessionId": session_id,
                "phone": phone,
                "colorReport": color_report,
                "meta": result["meta"],
                "genderCheck": result.get("genderCheck", {}),
                "files": result["files"],
            },
        )


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    server = HTTPServer(("127.0.0.1", PORT), Region25Handler)
    print(f"[region25-api] listening http://127.0.0.1:{PORT}")
    print(f"[region25-api] data dir: {DATA_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
