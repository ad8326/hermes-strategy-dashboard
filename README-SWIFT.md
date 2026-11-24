# Hermes 策略数据中心（macOS）

使用 Swift、SwiftUI 和 Apple Charts 构建的原生 macOS 策略仪表盘；不依赖浏览器、Python、JavaScript、第三方包或外部 CDN。

## 构建和启动

需要 macOS 13 或更高版本以及 Swift 5.9+（可通过 Xcode Command Line Tools 安装）。

```bash
swift run
./Packaging/build-macos-app.sh
open dist/HermesDashboard.app
```

应用包生成在 `dist/HermesDashboard.app`。项目静态数据位于 `Sources/HermesDashboard/Resources/dashboard-data.json`。实时行情与策略指标需要网络连接；行情服务不可用时会显示错误并保留上次成功的数据。行情快照和格林美历史 K 线以 SQLite 格式存储在 `~/Library/Application Support/HermesDashboard/dashboard.sqlite3`，应用重启后先显示缓存数据；旧版 JSON 缓存会在首次启动时导入数据库，原文件保留；纸盘账户数据可选读取自 `~/.hermes/paper_trader/portfolio.json`。

包含净值及交易图表、日期区间回测、FIFO 交易配对、隔夜预测估算、实时行情、格林美 RSI/KDJ/WR/BR 信号与回测、策略全景、演化时间线、交易记录和定时任务矩阵。

> 涨红跌绿（A 股惯例）。仅供策略研究参考，不构成投资建议。
