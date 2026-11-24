# 需求规格：macOS 本地应用 + 实时联网数据（SPEC-LIVE）

在现有静态看板基础上改造为 **macOS 可运行的本地应用**，支持实时联网获取行情数据。

## 1. 新增 `app.py`：本地服务（仅 Python 标准库，禁止第三方依赖）

- 基于 `http.server.ThreadingHTTPServer` + `BaseHTTPRequestHandler`，端口 8765
- 路由：
  - `GET /` → 返回 index.html
  - `GET /data.js`、`GET /backtest.js` → 返回对应静态文件
  - `GET /api/quotes?codes=sh600219,sz002340` → **实时行情代理**：请求腾讯行情接口 `https://qt.gtimg.cn/q=<codes>`（GBK 编码），解析后返回 JSON 数组，每条含 `{code, name, price, changePct, open, high, low, prevClose, time, volume}`。涨跌幅保留 2 位小数。解析失败或超时（5s）返回 `{"error": "..."}`，HTTP 200
  - `GET /api/portfolio` → 尝试读取 `~/.hermes/paper_trader/portfolio.json` 返回 `{cash, total_value, holdings:[...], updated_at}`；文件不存在或读取失败返回 `{"available": false}`（不报错、不崩溃）
- User-Agent 伪装浏览器，防止被行情接口拒绝
- 支持并发请求（ThreadingHTTPServer），日志静默（覆盖 log_message）

## 2. 修改 `index.html`：新增「📡 实时行情」区块（放在 KPI 卡片之后、净值图表之前）

- 监控标的固定列表（写入 JS 常量）：
  - 指数：上证指数 sh000001、创业板指 sz399006、中证红利 sh000922
  - 持仓复盘：南山铝业 sh600219、格林美 sz002340
  - 红塔创新：新亚强 sh603155、德才股份 sh605287、冰轮环境 sz000811、煜邦电力 sh688591、武汉天源 sz300355
- 页面加载后立即请求 `/api/quotes`，之后每 10 秒自动刷新
- 每个标的渲染一行：名称、代码、现价、涨跌幅、涨跌额、开盘/最高/最低，**涨红跌绿**（正 #f0506e / 负 #2ea86e，与现有 CSS 变量一致）
- 显示「上次更新时间 HH:MM:SS」与刷新倒计时；接口失败显示 ⚠️ 提示但不清空旧数据
- 新增「⏸/▶ 暂停刷新」按钮

## 3. 新增 `HermesDashboard.app`（macOS 应用包）

目录结构：
```
HermesDashboard.app/
  Contents/
    Info.plist（CFBundleName=HermesDashboard, CFBundleIdentifier=com.nick.hermesdashboard, LSUIElement=true）
    MacOS/launcher（可执行 bash 脚本）
    Resources/icon.icns（可选，没有就跳过）
```
- launcher 逻辑：`cd` 到项目目录 → 用 `/usr/local/bin/python3`（不存在则回退 `python3`）后台启动 `app.py`（端口 8765，若已被占用则先 `pkill -f "app.py"` 再启动）→ 等待 1.5 秒 → `open http://localhost:8765`
- 脚本加 `#!/bin/bash`，chmod +x

## 4. 约束
- 不破坏现有回测面板与全部原有功能；`data.js`、`backtest.js` 不改动
- 所有新增注释用中文；index.html 只在指定位置插入，不重排已有区块
- 完成后不提交 git，由主控验证
