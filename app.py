#!/usr/bin/env python3
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PORT = 8765
QUOTE_CODE_PATTERN = re.compile(r"^(?:sh|sz)\d{6}$")
QUOTE_PATTERN = re.compile(r'v_(sh|sz)(\d{6})="([^"]*)"')


def json_response(handler, payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(200)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def parse_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fetch_quotes(codes):
    if not codes or any(not QUOTE_CODE_PATTERN.fullmatch(code) for code in codes):
        raise ValueError("codes 参数无效")

    url = "https://qt.gtimg.cn/q=" + ",".join(codes)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Chrome/131.0 Safari/537.36"},
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        text = response.read().decode("gbk")

    records = {
        match.group(1) + match.group(2): match.group(3).split("~")
        for match in QUOTE_PATTERN.finditer(text)
    }
    quotes = []
    for code in codes:
        fields = records.get(code)
        if not fields or len(fields) <= 34 or not fields[1]:
            raise ValueError(f"{code} 行情数据解析失败")
        price = parse_number(fields[3])
        prev_close = parse_number(fields[4])
        if price is None or prev_close is None:
            raise ValueError(f"{code} 行情价格无效")
        change_pct = round((price - prev_close) / prev_close * 100, 2) if prev_close else 0
        quotes.append({
            "code": code,
            "name": fields[1],
            "price": price,
            "changePct": change_pct,
            "open": parse_number(fields[5]),
            "high": parse_number(fields[33]),
            "low": parse_number(fields[34]),
            "prevClose": prev_close,
            "time": fields[30],
            "volume": parse_number(fields[6]),
        })
    return quotes


def read_portfolio():
    path = Path.home() / ".hermes" / "paper_trader" / "portfolio.json"
    try:
        with path.open("r", encoding="utf-8") as portfolio_file:
            portfolio = json.load(portfolio_file)
        if not isinstance(portfolio, dict):
            return {"available": False}
        return {
            "cash": portfolio.get("cash"),
            "total_value": portfolio.get("total_value"),
            "holdings": portfolio.get("holdings", []),
            "updated_at": portfolio.get("updated_at"),
        }
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {"available": False}


class DashboardHandler(BaseHTTPRequestHandler):
    def log_message(self, format_string, *args):
        return

    def do_GET(self):
        parsed_url = urllib.parse.urlsplit(self.path)
        if parsed_url.path == "/":
            self.serve_static("index.html", "text/html; charset=utf-8")
        elif parsed_url.path in ("/data.js", "/backtest.js"):
            self.serve_static(parsed_url.path.lstrip("/"), "application/javascript; charset=utf-8")
        elif parsed_url.path == "/api/quotes":
            codes = urllib.parse.parse_qs(parsed_url.query).get("codes", [""])[0].split(",")
            try:
                json_response(self, fetch_quotes(codes))
            except (OSError, UnicodeError, ValueError, urllib.error.URLError) as error:
                json_response(self, {"error": str(error) or "行情数据请求失败"})
        elif parsed_url.path == "/api/portfolio":
            json_response(self, read_portfolio())
        elif parsed_url.path == "/api/gm_strategy":
            # 格林美 RSI+KDJ 双超卖策略：实时指标 + 回测统计
            try:
                import gm_strategy
                json_response(self, gm_strategy.full_snapshot())
            except Exception as error:  # 数据源异常时降级，不崩溃
                json_response(self, {"error": str(error)})
        else:
            self.send_error(404)

    def serve_static(self, filename, content_type):
        try:
            body = (ROOT / filename).read_bytes()
        except OSError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), DashboardHandler).serve_forever()
