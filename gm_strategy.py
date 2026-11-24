#!/usr/bin/env python3
"""
RSI+KDJ 双超卖抄底策略（格林美 002340 专属）
规则来自同花顺「RSI+KDJ买入法」：
  买入: RSI(6) < 16 且 J值(9,3,3) < 10  —— 双超卖抄底
  卖出: WR(10) < 20 或 BR(26) 上穿 160  —— 过热/反转离场
指标口径与同花顺/通达信一致: SMA(X,N,M) 递推平滑
仅用 Python 标准库
"""
import json
import urllib.request


def fetch_kline(code="sz002340", count=320):
    """腾讯日 K 接口（前复权），返回 [{date, open, close, high, low}]"""
    url = f"https://ifzq.gtimg.cn/appstock/app/fqkline/get?param={code},day,,,{count},qfq"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        d = json.loads(resp.read().decode("utf-8"))
    data = d["data"][code]
    key = "qfqday" if "qfqday" in data else "day"
    bars = []
    for row in data[key]:
        bars.append({
            "date": row[0],
            "open": float(row[1]),
            "close": float(row[2]),
            "high": float(row[3]),
            "low": float(row[4]),
        })
    return bars


def sma_series(x, n, m):
    """通达信 SMA(X,N,M): Y = (M*X + (N-M)*Y') / N"""
    out = []
    y = None
    for v in x:
        if y is None:
            y = v
        else:
            y = (m * v + (n - m) * y) / n
        out.append(y)
    return out


def compute_indicators(bars):
    """计算 RSI(6) / KDJ(9,3,3) / WR(10) / BR(26)"""
    closes = [b["close"] for b in bars]
    highs = [b["high"] for b in bars]
    lows = [b["low"] for b in bars]
    n = len(bars)

    # RSI(6): SMA(MAX(C-LC,0),6,1) / SMA(ABS(C-LC),6,1) * 100
    up, dn = [0.0], [0.0]
    for i in range(1, n):
        chg = closes[i] - closes[i - 1]
        up.append(max(chg, 0.0))
        dn.append(abs(chg))
    up_s = sma_series(up, 6, 1)
    dn_s = sma_series(dn, 6, 1)
    rsi = [up_s[i] / dn_s[i] * 100 if dn_s[i] else 100.0 for i in range(n)]

    # KDJ(9,3,3)
    k_vals, d_vals = [], []
    k = d = 50.0
    for i in range(n):
        hh = max(highs[max(0, i - 8):i + 1])
        ll = min(lows[max(0, i - 8):i + 1])
        rsv = (closes[i] - ll) / (hh - ll) * 100 if hh != ll else 50.0
        k = (1 * rsv + 2 * k) / 3       # SMA(RSV,3,1)
        d = (1 * k + 2 * d) / 3         # SMA(K,3,1)
        k_vals.append(k)
        d_vals.append(d)
    j = [3 * k_vals[i] - 2 * d_vals[i] for i in range(n)]

    # WR(10)
    wr = []
    for i in range(n):
        hh = max(highs[max(0, i - 9):i + 1])
        ll = min(lows[max(0, i - 9):i + 1])
        wr.append((hh - closes[i]) / (hh - ll) * 100 if hh != ll else 50.0)

    # BR(26): SUM(MAX(0,H-LC),26) / SUM(MAX(0,LC-L),26) * 100
    br = []
    for i in range(n):
        if i == 0:
            br.append(100.0)
            continue
        window_hi = [max(0.0, highs[t] - closes[t - 1]) for t in range(max(1, i - 25), i + 1)]
        window_lo = [max(0.0, closes[t - 1] - lows[t]) for t in range(max(1, i - 25), i + 1)]
        s_hi, s_lo = sum(window_hi), sum(window_lo)
        br.append(s_hi / s_lo * 100 if s_lo else 400.0)

    return rsi, j, wr, br


def backtest(bars, rsi, j, wr, br, start="2026-03-23"):
    """
    信号口径（与同花顺一致，收盘确认、次日开盘执行）:
      买入: RSI<16 且 J<10
      卖出: WR<20 或 BR 上穿 160（今日 BR>160 且昨日 BR<=160）
    返回交易明细与统计，空仓段与基准（买入持有）对比
    """
    trades = []
    holding = False
    entry_price = entry_date = None
    pending_exit = False

    for i in range(1, len(bars)):
        date = bars[i]["date"]
        if date < start:
            continue
        prev = i - 1
        # 信号在昨收盘确认，今日开盘执行
        buy_signal = rsi[prev] < 16 and j[prev] < 10
        br_cross = br[prev] > 160 and br[prev - 1] <= 160
        sell_signal = wr[prev] < 20 or br_cross

        if holding:
            if sell_signal:
                exit_price = bars[i]["open"]
                ret = (exit_price / entry_price - 1) * 100
                trades.append({
                    "entryDate": entry_date, "exitDate": date,
                    "entryPrice": round(entry_price, 3), "exitPrice": round(exit_price, 3),
                    "returnPct": round(ret, 2),
                    "holdingDays": i - _idx(bars, entry_date),
                    "exitReason": "WR超热(<20)" if wr[prev] < 20 else "BR上穿160",
                })
                holding = False
        else:
            if buy_signal:
                holding = True
                entry_price = bars[i]["open"]
                entry_date = date

    # 期末仍持仓 → 按最后收盘价浮动盈亏
    open_trade = None
    if holding:
        last = bars[-1]
        ret = (last["close"] / entry_price - 1) * 100
        open_trade = {
            "entryDate": entry_date, "entryPrice": round(entry_price, 3),
            "floatReturnPct": round(ret, 2),
        }

    wins = [t for t in trades if t["returnPct"] > 0]
    stats = {
        "trades": trades,
        "count": len(trades),
        "winRate": round(len(wins) / len(trades) * 100, 1) if trades else None,
        "avgReturn": round(sum(t["returnPct"] for t in trades) / len(trades), 2) if trades else None,
        "best": max((t["returnPct"] for t in trades), default=None),
        "worst": min((t["returnPct"] for t in trades), default=None),
        "openTrade": open_trade,
    }
    # 基准: 区间首日开盘买入持有至最后收盘
    base_bars = [b for b in bars if b["date"] >= start]
    if base_bars:
        stats["buyHoldReturn"] = round((base_bars[-1]["close"] / base_bars[0]["open"] - 1) * 100, 2)
    return stats


def _idx(bars, date):
    for i, b in enumerate(bars):
        if b["date"] == date:
            return i
    return 0


def full_snapshot(code="sz002340", backtest_start="2026-03-23"):
    """供 app.py 调用：指标现值 + 当前信号 + 回测统计"""
    bars = fetch_kline(code)
    rsi, j, wr, br = compute_indicators(bars)
    last = len(bars) - 1
    stats = backtest(bars, rsi, j, wr, br, backtest_start)
    # 当前信号状态（以最新收盘指标判断）
    if rsi[last] < 16 and j[last] < 10:
        signal = {"state": "buy", "text": "双超卖买入信号区 (RSI<16 且 J<10)"}
    elif wr[last] < 20:
        signal = {"state": "sell", "text": "WR 超热区 (<20)，持仓者考虑离场"}
    elif br[last] > 160:
        signal = {"state": "watch", "text": "BR 高位 (>160)，关注上穿 160 的离场确认"}
    else:
        signal = {"state": "neutral", "text": "信号中性，等待双超卖"}
    # 近 60 日指标序列（供前端画迷你图）
    series = [{
        "date": bars[t]["date"],
        "rsi": round(rsi[t], 1), "j": round(j[t], 1),
        "wr": round(wr[t], 1), "br": round(br[t], 1),
        "close": bars[t]["close"],
    } for t in range(max(0, last - 59), last + 1)]
    return {
        "code": code,
        "name": "格林美" if code == "sz002340" else code,
        "date": bars[last]["date"],
        "close": bars[last]["close"],
        "indicators": {"rsi": round(rsi[last], 1), "j": round(j[last], 1),
                       "wr": round(wr[last], 1), "br": round(br[last], 1)},
        "signal": signal,
        "backtest": stats,
        "series": series,
    }


if __name__ == "__main__":
    snap = full_snapshot()
    print(json.dumps(snap, ensure_ascii=False, indent=1)[:2000])
