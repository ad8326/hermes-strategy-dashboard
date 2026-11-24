import Charts
import Foundation
import SwiftUI

@main
struct HermesDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1050, minHeight: 760)
                .preferredColorScheme(.dark)
        }
    }
}

private enum Palette {
    static let background = Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)
    static let panel = Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255)
    static let panelAlt = Color(red: 28 / 255, green: 35 / 255, blue: 51 / 255)
    static let border = Color(red: 45 / 255, green: 51 / 255, blue: 59 / 255)
    static let text = Color(red: 230 / 255, green: 237 / 255, blue: 243 / 255)
    static let muted = Color(red: 139 / 255, green: 148 / 255, blue: 158 / 255)
    static let up = Color(red: 240 / 255, green: 80 / 255, blue: 110 / 255)
    static let down = Color(red: 46 / 255, green: 168 / 255, blue: 110 / 255)
    static let accent = Color(red: 78 / 255, green: 142 / 255, blue: 247 / 255)
    static let gold = Color(red: 217 / 255, green: 165 / 255, blue: 63 / 255)
}

private struct DashboardData: Decodable {
    let nav_series: [NavPoint]
    let transactions: [Transaction]
    let meta: Metadata
    let kpis: KPIData
    let strategies: [Strategy]
    let timeline: [TimelineEntry]
    let jobs: [Job]
}

private struct NavPoint: Decodable, Identifiable {
    let date: String
    let nav: Double
    let ret: Double
    var id: String { date }
}

private struct Transaction: Decodable, Identifiable {
    let date: String
    let action: String
    let code: String
    let name: String
    let price: Double
    let shares: Int
    let pnl: Double?
    let pnl_pct: Double?
    let reason: String
    var id: String { "\(date)-\(code)-\(action)-\(shares)" }
}

private struct Metadata: Decodable {
    let source: String
    let period: String
    let generated: String
}

private struct KPIData: Decodable {
    let days: Int
    let total_runs: Int
    let nav: NavKPIs
    let trades: TradeKPIs
    let overnight_acc: OvernightKPIs
    let demon: DemonKPIs
    let tunes: Int
}

private struct NavKPIs: Decodable {
    let initial: Double
    let current: Double
    let return_pct: Double
    let max_dd: Double
}

private struct TradeKPIs: Decodable {
    let total: Int
    let buys: Int
    let sells: Int
    let win_rate: Double
    let realized: Double
    let best: TradeHighlight
    let worst: TradeHighlight
}

private struct TradeHighlight: Decodable {
    let name: String
    let pct: Double
    let pnl: Double
}

private struct OvernightKPIs: Decodable {
    let hits: Double
    let total: Double
    let rate: Double
}

private struct DemonKPIs: Decodable {
    let picks: Int
    let wins: Int
    let rate: Double
    let pnl: Double
}

private struct Strategy: Decodable, Identifiable {
    let id: String
    let icon: String
    let name: String
    let category: String
    let status: String
    let runs: Int
    let desc: String
    let method: [String]
    let perf: String
}

private struct TimelineEntry: Decodable, Identifiable {
    let date: String
    let tag: String
    let title: String
    let desc: String
    var id: String { "\(date)-\(title)" }
}

private struct Job: Decodable, Identifiable {
    let name: String
    let sched: String
    let runs: Int
    let ok: Bool
    var id: String { name }
}

private struct Quote: Codable, Identifiable {
    let code: String
    let name: String
    let price: Double
    let changePct: Double
    let open: Double?
    let high: Double?
    let low: Double?
    let prevClose: Double
    let time: String
    let volume: Double?
    var id: String { code }
    var change: Double { price - prevClose }
}

private struct WatchedStock: Identifiable {
    let code: String
    let name: String
    let group: String
    var id: String { code }
}

private struct PortfolioSnapshot {
    let cash: Double?
    let totalValue: Double?
    let updatedAt: String?
    let holdingCount: Int
}

private struct PairedTrade: Identifiable {
    let buyDate: String
    let sellDate: String
    let name: String
    let code: String
    let shares: Int
    let holdingDays: Int
    let returnPct: Double
    var id: String { "\(buyDate)-\(sellDate)-\(code)-\(shares)" }
}

private struct BacktestReport {
    let metrics: [Metric]
    let nav: [NavPoint]
    let drawdowns: [Double]
    let pairs: [PairedTrade]
    let cumulativeReturn: Double?
    let averageHoldingReturn: Double?
}

private struct Metric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let color: Color
    var id: String { title }
}

private struct GMBar: Codable {
    let date: String
    let open: Double
    let close: Double
    let high: Double
    let low: Double
}

private struct GMTrade: Identifiable {
    let entryDate: String
    let exitDate: String
    let entryPrice: Double
    let exitPrice: Double
    let holdingDays: Int
    let returnPct: Double
    let exitReason: String
    var id: String { "\(entryDate)-\(exitDate)" }
}

private struct GMPoint: Identifiable {
    let date: String
    let rsi: Double
    let j: Double
    var id: String { date }
}

private struct GMSnapshot {
    let date: String
    let close: Double
    let rsi: Double
    let j: Double
    let wr: Double
    let br: Double
    let state: String
    let signal: String
    let points: [GMPoint]
    let trades: [GMTrade]
    let openReturn: Double?
    let buyHoldReturn: Double?
}

private struct QuoteSnapshot: Codable {
    let fetchedAt: Date
    let quotes: [Quote]
}

private struct QuoteArchive: Codable {
    var snapshots: [QuoteSnapshot]
}

private struct GMArchive: Codable {
    var updatedAt: Date
    var bars: [GMBar]
}

@MainActor
private final class DashboardModel: ObservableObject {
    @Published private(set) var data: DashboardData?
    @Published private(set) var loadError: String?
    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var quoteError: String?
    @Published private(set) var lastQuoteUpdate: Date?
    @Published var isQuoteRefreshPaused = false
    @Published private(set) var portfolio: PortfolioSnapshot?
    @Published private(set) var portfolioUnavailable = false
    @Published private(set) var gmSnapshot: GMSnapshot?
    @Published private(set) var gmError: String?
    @Published private(set) var cacheError: String?
    @Published private(set) var cacheLocation: String?
    @Published private(set) var cachedQuoteSnapshotCount = 0
    @Published private(set) var cachedGMBarCount = 0
    @Published var backtestStart = Date()
    @Published var backtestEnd = Date()
    @Published private(set) var backtestReport: BacktestReport?
    @Published var backtestError: String?
    private var cacheStore: LocalSQLiteStore?

    let watchedStocks = [
        WatchedStock(code: "sh000001", name: "上证指数", group: "指数"),
        WatchedStock(code: "sz399006", name: "创业板指", group: "指数"),
        WatchedStock(code: "sh000922", name: "中证红利", group: "指数"),
        WatchedStock(code: "sh600219", name: "南山铝业", group: "持仓复盘"),
        WatchedStock(code: "sz002340", name: "格林美", group: "持仓复盘"),
        WatchedStock(code: "sh603155", name: "新亚强", group: "红塔创新"),
        WatchedStock(code: "sh605287", name: "德才股份", group: "红塔创新"),
        WatchedStock(code: "sz000811", name: "冰轮环境", group: "红塔创新"),
        WatchedStock(code: "sh688591", name: "煜邦电力", group: "红塔创新"),
        WatchedStock(code: "sz300355", name: "武汉天源", group: "红塔创新")
    ]

    init() {
        do {
            let resourceURL = Bundle.module.url(forResource: "dashboard-data", withExtension: "json")
                ?? Bundle.main.url(forResource: "dashboard-data", withExtension: "json")
            guard let resourceURL else { throw DashboardError.missingData }
            data = try JSONDecoder().decode(DashboardData.self, from: Data(contentsOf: resourceURL))
            if let first = data?.nav_series.first, let last = data?.nav_series.last {
                backtestStart = parseDate(first.date) ?? Date()
                backtestEnd = parseDate(last.date) ?? Date()
            }
        } catch {
            loadError = "看板数据加载失败：\(error.localizedDescription)"
        }
        do {
            let store = try LocalSQLiteStore()
            cacheStore = store
            cacheLocation = store.databaseURL.path
            try importLegacyCache(using: store)
            if let latest = try store.latestQuoteSnapshot() {
                quotes = Dictionary(uniqueKeysWithValues: latest.quotes.map { ($0.code, makeQuote($0)) })
                lastQuoteUpdate = latest.fetchedAt
            }
            cachedQuoteSnapshotCount = try store.quoteSnapshotCount()
            let cachedBars = try store.loadGMBars()
            if !cachedBars.isEmpty {
                guard cachedBars.count > 30 else {
                    throw DashboardError.badResponse("本地格林美日 K 缓存数据不足")
                }
                gmSnapshot = try makeGMSnapshot(cachedBars.map(makeGMBar))
            }
            cachedGMBarCount = cachedBars.count
        } catch {
            cacheError = "读取本地缓存失败：\(error.localizedDescription)"
        }
    }

    func start() async {
        await refreshQuotes()
        await refreshPortfolio()
        await refreshGM()
        runBacktest()
    }

    func refreshQuotes() async {
        let codes = watchedStocks.map(\.code)
        do {
            guard let url = URL(string: "https://qt.gtimg.cn/q=" + codes.joined(separator: ",")) else {
                throw DashboardError.invalidURL
            }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Chrome/131.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw DashboardError.badResponse("行情服务返回错误状态")
            }
            guard let text = String(data: responseData, encoding: .gb_18030_2000) else {
                throw DashboardError.badResponse("行情数据编码无法识别")
            }
            let parsed = try parseQuotes(text, expectedCodes: codes)
            quotes = Dictionary(uniqueKeysWithValues: parsed.map { ($0.code, $0) })
            quoteError = nil
            let fetchedAt = Date()
            lastQuoteUpdate = fetchedAt
            do {
                try persistQuotes(parsed, fetchedAt: fetchedAt)
                cacheError = nil
            } catch {
                cacheError = "行情已更新，但本地缓存保存失败：\(error.localizedDescription)"
            }
        } catch {
            quoteError = "行情获取失败：\(error.localizedDescription)"
        }
    }

    func refreshPortfolio() async {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/paper_trader/portfolio.json")
        do {
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let record = raw as? [String: Any] else { throw DashboardError.invalidPortfolio }
            let holdings = record["holdings"] as? [Any] ?? []
            portfolio = PortfolioSnapshot(
                cash: (record["cash"] as? NSNumber)?.doubleValue,
                totalValue: (record["total_value"] as? NSNumber)?.doubleValue,
                updatedAt: record["updated_at"] as? String,
                holdingCount: holdings.count
            )
            portfolioUnavailable = false
        } catch {
            portfolio = nil
            portfolioUnavailable = true
        }
    }

    func refreshGM() async {
        do {
            let bars = try await fetchGMBars()
            gmSnapshot = try makeGMSnapshot(bars)
            gmError = nil
            do {
                try persistGMBars(bars, updatedAt: Date())
                cacheError = nil
            } catch {
                cacheError = "格林美数据已更新，但本地缓存保存失败：\(error.localizedDescription)"
            }
        } catch {
            gmError = "格林美策略数据暂不可用：\(error.localizedDescription)"
        }
    }

    func setBacktestRange(months: Int?) {
        guard let points = data?.nav_series, let first = points.first, let last = points.last else { return }
        backtestEnd = parseDate(last.date) ?? Date()
        guard let months else {
            backtestStart = parseDate(first.date) ?? Date()
            runBacktest()
            return
        }
        let end = parseDate(last.date) ?? Date()
        let proposed = Calendar(identifier: .gregorian).date(byAdding: .month, value: -months, to: end) ?? end
        let earliest = parseDate(first.date) ?? end
        backtestStart = max(proposed, earliest)
        runBacktest()
    }

    func runBacktest() {
        guard let data else { return }
        let start = dateString(backtestStart)
        let end = dateString(backtestEnd)
        guard start <= end else {
            backtestError = "开始日期不能晚于结束日期。"
            backtestReport = nil
            return
        }
        let points = data.nav_series.filter { $0.date >= start && $0.date <= end }
        guard !points.isEmpty else {
            backtestError = "所选区间内没有净值数据。"
            backtestReport = nil
            return
        }
        let trades = data.transactions.filter { $0.date >= start && $0.date <= end }
        let values = points.map(\.nav)
        let dailyReturns = zip(values.dropFirst(), values).compactMap { pair -> Double? in
            let (current, previous) = pair
            return previous == 0 ? nil : current / previous - 1
        }
        let cumulative = values.count > 1 && values[0] != 0 ? values.last! / values[0] - 1 : (values.isEmpty ? nil : 0)
        let annualized = values.count > 1 && values[0] > 0 && values.last! > 0
            ? pow(values.last! / values[0], 252 / Double(values.count - 1)) - 1 : nil
        let mean = dailyReturns.isEmpty ? nil : dailyReturns.reduce(0, +) / Double(dailyReturns.count)
        let variance = mean.map { average in
            dailyReturns.reduce(0) { $0 + pow($1 - average, 2) } / Double(dailyReturns.count)
        }
        let volatility = variance.map { sqrt($0) * sqrt(252) }
        let sharpe: Double? = {
            guard let mean, let variance, variance > 0 else { return nil }
            return (mean - 0.015 / 252) / sqrt(variance) * sqrt(252)
        }()
        var peak = -Double.infinity
        var peakDate: String?
        var maxDrawdown = 0.0
        var drawdownStart: String?
        var drawdownEnd: String?
        let drawdowns = points.map { point -> Double in
            if point.nav > peak {
                peak = point.nav
                peakDate = point.date
            }
            let drawdown = peak == 0 ? 0 : point.nav / peak - 1
            if drawdown < maxDrawdown {
                maxDrawdown = drawdown
                drawdownStart = peakDate
                drawdownEnd = point.date
            }
            return drawdown
        }
        let sells = trades.filter { $0.action == "SELL" }
        let wins = sells.compactMap { ($0.pnl_pct ?? 0) > 0 ? $0.pnl_pct : nil }
        let losses = sells.compactMap { ($0.pnl_pct ?? 0) < 0 ? $0.pnl_pct : nil }
        let avgWin = wins.isEmpty ? nil : wins.reduce(0, +) / Double(wins.count)
        let avgLoss = losses.isEmpty ? nil : losses.reduce(0, +) / Double(losses.count)
        let best = sells.max { ($0.pnl_pct ?? -.infinity) < ($1.pnl_pct ?? -.infinity) }
        let worst = sells.min { ($0.pnl_pct ?? .infinity) < ($1.pnl_pct ?? .infinity) }
        let realized = sells.reduce(0) { $0 + ($1.pnl ?? 0) }
        let pairs = pairTrades(trades)
        let averageHoldingReturn = pairs.isEmpty ? nil : pairs.map(\.returnPct).reduce(0, +) / Double(pairs.count)
        let averageHoldingDays = pairs.isEmpty ? nil : Double(pairs.map(\.holdingDays).reduce(0, +)) / Double(pairs.count)
        let totalDays = max(1, data.nav_series.count)
        let ratio = Double(points.count) / Double(totalDays)
        let estimatedHits = data.kpis.overnight_acc.hits * ratio
        let estimatedTotal = data.kpis.overnight_acc.total * ratio
        let accuracy = estimatedTotal == 0 ? nil : estimatedHits / estimatedTotal

        let metrics = [
            Metric(title: "累计收益率", value: percent(cumulative), detail: "按区间首尾净值计算", color: returnColor(cumulative)),
            Metric(title: "年化收益率", value: percent(annualized), detail: "按 252 个交易日折算", color: returnColor(annualized)),
            Metric(title: "最大回撤", value: percent(maxDrawdown), detail: drawdownStart.map { "\($0) 至 \(drawdownEnd ?? "")" } ?? "区间内无回撤", color: Palette.down),
            Metric(title: "年化波动率", value: percent(volatility), detail: "日收益率标准差 × √252", color: Palette.gold),
            Metric(title: "夏普比率", value: number(sharpe), detail: "无风险利率 1.5%", color: returnColor(sharpe)),
            Metric(title: "卡玛比率", value: maxDrawdown < 0 ? number(annualized.map { $0 / abs(maxDrawdown) }) : "—", detail: "年化收益 / 最大回撤", color: Palette.accent),
            Metric(title: "盈利日占比", value: dailyReturns.isEmpty ? "—" : percent(Double(dailyReturns.filter { $0 > 0 }.count) / Double(dailyReturns.count)), detail: "区间日收益大于零的比例", color: Palette.accent),
            Metric(title: "平仓交易次数", value: "\(sells.count)", detail: "仅统计区间内卖出", color: Palette.text),
            Metric(title: "交易胜率", value: sells.isEmpty ? "—" : percent(Double(wins.count) / Double(sells.count)), detail: "\(wins.count) 笔盈利 / \(sells.count) 笔平仓", color: Palette.accent),
            Metric(title: "平均盈利 / 平均亏损", value: "\(percent(avgWin.map { $0 / 100 })) / \(percent(avgLoss.map { $0 / 100 }))", detail: "按平仓盈亏率", color: Palette.gold),
            Metric(title: "盈亏比", value: avgWin != nil && avgLoss != nil && avgLoss != 0 ? number(avgWin! / abs(avgLoss!)) : "—", detail: "平均盈利 / 平均亏损", color: Palette.accent),
            Metric(title: "累计已实现盈亏", value: money(realized), detail: "区间内 SELL 盈亏金额合计", color: returnColor(realized)),
            Metric(title: "最佳 / 最差单笔", value: "\(best.map { percent(($0.pnl_pct ?? 0) / 100) } ?? "—") / \(worst.map { percent(($0.pnl_pct ?? 0) / 100) } ?? "—")", detail: [best?.name, worst?.name].compactMap { $0 }.joined(separator: " / "), color: Palette.gold),
            Metric(title: "隔夜预测准确率", value: percent(accuracy), detail: "估算 \(number(estimatedHits)) / \(number(estimatedTotal)) 次", color: Palette.gold),
            Metric(title: "FIFO 配对笔数", value: "\(pairs.count)", detail: "按代码、先入先出配对", color: Palette.text),
            Metric(title: "平均持有天数", value: number(averageHoldingDays), detail: "自然日", color: Palette.text),
            Metric(title: "平均持有期收益", value: percent(averageHoldingReturn.map { $0 / 100 }), detail: "配对交易等权平均", color: returnColor(averageHoldingReturn))
        ]
        backtestReport = BacktestReport(
            metrics: metrics,
            nav: points,
            drawdowns: drawdowns,
            pairs: pairs,
            cumulativeReturn: cumulative,
            averageHoldingReturn: averageHoldingReturn
        )
        backtestError = nil
    }

    private func parseQuotes(_ text: String, expectedCodes: [String]) throws -> [Quote] {
        let regex = try NSRegularExpression(pattern: #"v_(sh|sz)(\d{6})="([^"]*)""#)
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let records = Dictionary(uniqueKeysWithValues: matches.compactMap { match -> (String, [String])? in
            guard match.numberOfRanges == 4 else { return nil }
            let code = nsText.substring(with: match.range(at: 1)) + nsText.substring(with: match.range(at: 2))
            let fields = nsText.substring(with: match.range(at: 3)).components(separatedBy: "~")
            return (code, fields)
        })
        return try expectedCodes.map { code in
            guard let fields = records[code], fields.count > 34,
                  let price = Double(fields[3]), let previous = Double(fields[4]), !fields[1].isEmpty else {
                throw DashboardError.badResponse("\(code) 行情数据解析失败")
            }
            return Quote(
                code: code,
                name: fields[1],
                price: price,
                changePct: previous == 0 ? 0 : ((price - previous) / previous * 100).rounded(toPlaces: 2),
                open: Double(fields[5]),
                high: Double(fields[33]),
                low: Double(fields[34]),
                prevClose: previous,
                time: fields[30],
                volume: Double(fields[6])
            )
        }
    }

    private func persistQuotes(_ quotes: [Quote], fetchedAt: Date) throws {
        guard let cacheStore else { throw DashboardError.cacheUnavailable }
        let rows = quotes.map {
            StoredQuote(
                code: $0.code, name: $0.name, price: $0.price, changePct: $0.changePct,
                open: $0.open, high: $0.high, low: $0.low, prevClose: $0.prevClose,
                time: $0.time, volume: $0.volume
            )
        }
        try cacheStore.saveQuoteSnapshot(StoredQuoteSnapshot(fetchedAt: fetchedAt, quotes: rows))
        cachedQuoteSnapshotCount = try cacheStore.quoteSnapshotCount()
    }

    private func persistGMBars(_ fetchedBars: [GMBar], updatedAt: Date) throws {
        guard let cacheStore else { throw DashboardError.cacheUnavailable }
        let rows = fetchedBars.map {
            StoredGMBar(date: $0.date, open: $0.open, close: $0.close, high: $0.high, low: $0.low)
        }
        try cacheStore.upsertGMBars(rows, updatedAt: updatedAt)
        cachedGMBarCount = try cacheStore.gmBarCount()
    }

    private func importLegacyCache(using store: LocalSQLiteStore) throws {
        let directory = store.databaseURL.deletingLastPathComponent()
        let quoteURL = directory.appendingPathComponent("quote-history.json")
        if try store.quoteSnapshotCount() == 0,
           FileManager.default.fileExists(atPath: quoteURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(QuoteArchive.self, from: Data(contentsOf: quoteURL))
            let snapshots = archive.snapshots.map { snapshot in
                StoredQuoteSnapshot(
                    fetchedAt: snapshot.fetchedAt,
                    quotes: snapshot.quotes.map {
                        StoredQuote(
                            code: $0.code, name: $0.name, price: $0.price, changePct: $0.changePct,
                            open: $0.open, high: $0.high, low: $0.low, prevClose: $0.prevClose,
                            time: $0.time, volume: $0.volume
                        )
                    }
                )
            }
            try store.saveQuoteSnapshots(snapshots)
        }

        let gmURL = directory.appendingPathComponent("gm-kline-history.json")
        if try store.gmBarCount() == 0,
           FileManager.default.fileExists(atPath: gmURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(GMArchive.self, from: Data(contentsOf: gmURL))
            let bars = archive.bars.map {
                StoredGMBar(date: $0.date, open: $0.open, close: $0.close, high: $0.high, low: $0.low)
            }
            try store.upsertGMBars(bars, updatedAt: archive.updatedAt)
        }
    }

    private func makeQuote(_ quote: StoredQuote) -> Quote {
        Quote(
            code: quote.code, name: quote.name, price: quote.price, changePct: quote.changePct,
            open: quote.open, high: quote.high, low: quote.low, prevClose: quote.prevClose,
            time: quote.time, volume: quote.volume
        )
    }

    private func makeGMBar(_ bar: StoredGMBar) -> GMBar {
        GMBar(date: bar.date, open: bar.open, close: bar.close, high: bar.high, low: bar.low)
    }

    private func pairTrades(_ transactions: [Transaction]) -> [PairedTrade] {
        var lots: [String: [Lot]] = [:]
        var results: [PairedTrade] = []
        let ordered = transactions.enumerated().sorted {
            $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date
        }
        for (_, transaction) in ordered {
            if transaction.action == "BUY" {
                lots[transaction.code, default: []].append(Lot(
                    date: transaction.date, name: transaction.name,
                    price: transaction.price, shares: transaction.shares
                ))
                continue
            }
            guard transaction.action == "SELL" else { continue }
            var remaining = transaction.shares
            while remaining > 0, var queue = lots[transaction.code], !queue.isEmpty {
                let lot = queue[0]
                let matched = min(remaining, lot.shares)
                let holdingDays = max(0, calendarDays(from: lot.date, to: transaction.date))
                results.append(PairedTrade(
                    buyDate: lot.date, sellDate: transaction.date,
                    name: transaction.name.isEmpty ? lot.name : transaction.name,
                    code: transaction.code, shares: matched, holdingDays: holdingDays,
                    returnPct: lot.price == 0 ? 0 : (transaction.price / lot.price - 1) * 100
                ))
                queue[0].shares -= matched
                remaining -= matched
                if queue[0].shares <= 0 { queue.removeFirst() }
                lots[transaction.code] = queue
            }
        }
        return results
    }

    private func fetchGMBars() async throws -> [GMBar] {
        var components = URLComponents(string: "https://ifzq.gtimg.cn/appstock/app/fqkline/get")!
        components.queryItems = [URLQueryItem(name: "param", value: "sz002340,day,,,320,qfq")]
        guard let url = components.url else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DashboardError.badResponse("K 线服务返回错误状态")
        }
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any],
              let allData = root["data"] as? [String: Any],
              let stock = allData["sz002340"] as? [String: Any],
              let rows = (stock["qfqday"] ?? stock["day"]) as? [[Any]] else {
            throw DashboardError.badResponse("无法读取格林美日 K 数据")
        }
        let bars = rows.compactMap { row -> GMBar? in
            guard row.count >= 5,
                  let date = row[0] as? String,
                  let open = doubleValue(row[1]),
                  let close = doubleValue(row[2]),
                  let high = doubleValue(row[3]),
                  let low = doubleValue(row[4]) else { return nil }
            return GMBar(date: date, open: open, close: close, high: high, low: low)
        }
        guard bars.count > 30 else { throw DashboardError.badResponse("格林美 K 线数据不足") }
        return bars
    }

    private func makeGMSnapshot(_ bars: [GMBar]) throws -> GMSnapshot {
        let closes = bars.map(\.close)
        let highs = bars.map(\.high)
        let lows = bars.map(\.low)
        let changes = closes.indices.map { index in index == 0 ? 0 : closes[index] - closes[index - 1] }
        let upSmooth = sma(changes.map { max($0, 0) }, period: 6)
        let absSmooth = sma(changes.map(abs), period: 6)
        let rsi = closes.indices.map { absSmooth[$0] == 0 ? 100 : upSmooth[$0] / absSmooth[$0] * 100 }
        var kValues: [Double] = []
        var dValues: [Double] = []
        var k = 50.0
        var d = 50.0
        for index in bars.indices {
            let upper = highs[max(0, index - 8)...index].max() ?? highs[index]
            let lower = lows[max(0, index - 8)...index].min() ?? lows[index]
            let rsv = upper == lower ? 50 : (closes[index] - lower) / (upper - lower) * 100
            k = (rsv + 2 * k) / 3
            d = (k + 2 * d) / 3
            kValues.append(k)
            dValues.append(d)
        }
        let jValues = bars.indices.map { 3 * kValues[$0] - 2 * dValues[$0] }
        let wr = bars.indices.map { index -> Double in
            let upper = highs[max(0, index - 9)...index].max() ?? highs[index]
            let lower = lows[max(0, index - 9)...index].min() ?? lows[index]
            return upper == lower ? 50 : (upper - closes[index]) / (upper - lower) * 100
        }
        let br = bars.indices.map { index -> Double in
            guard index > 0 else { return 100 }
            let first = max(1, index - 25)
            var highSum = 0.0
            var lowSum = 0.0
            for barIndex in first...index {
                highSum += max(0, highs[barIndex] - closes[barIndex - 1])
                lowSum += max(0, closes[barIndex - 1] - lows[barIndex])
            }
            return lowSum == 0 ? 400 : highSum / lowSum * 100
        }
        let last = bars.count - 1
        var holding = false
        var entryPrice = 0.0
        var entryIndex = 0
        var entryDate = ""
        var trades: [GMTrade] = []
        for index in 1..<bars.count where bars[index].date >= "2026-03-23" {
            let previous = index - 1
            let buy = rsi[previous] < 16 && jValues[previous] < 10
            let brCross = br[previous] > 160 && br[previous - 1] <= 160
            let sell = wr[previous] < 20 || brCross
            if holding {
                if sell {
                    let exitPrice = bars[index].open
                    trades.append(GMTrade(
                        entryDate: entryDate, exitDate: bars[index].date, entryPrice: entryPrice,
                        exitPrice: exitPrice, holdingDays: index - entryIndex,
                        returnPct: (exitPrice / entryPrice - 1) * 100,
                        exitReason: wr[previous] < 20 ? "WR 超热区" : "BR 上穿 160"
                    ))
                    holding = false
                }
            } else if buy {
                holding = true
                entryPrice = bars[index].open
                entryIndex = index
                entryDate = bars[index].date
            }
        }
        let openReturn = holding ? (bars[last].close / entryPrice - 1) * 100 : nil
        let inRange = bars.filter { $0.date >= "2026-03-23" }
        let buyHold = inRange.first.map { (inRange.last!.close / $0.open - 1) * 100 }
        let state: String
        let signal: String
        if rsi[last] < 16 && jValues[last] < 10 {
            state = "买入关注"
            signal = "双超卖区间（RSI < 16 且 J < 10）"
        } else if wr[last] < 20 {
            state = "卖出关注"
            signal = "WR 进入超热区（< 20）"
        } else if br[last] > 160 {
            state = "观察"
            signal = "BR 高于 160，关注离场确认"
        } else {
            state = "中性"
            signal = "等待双超卖信号"
        }
        let points = (max(0, last - 59)...last).map { index in
            GMPoint(date: bars[index].date, rsi: rsi[index], j: jValues[index])
        }
        return GMSnapshot(
            date: bars[last].date, close: bars[last].close,
            rsi: rsi[last], j: jValues[last], wr: wr[last], br: br[last],
            state: state, signal: signal, points: points, trades: trades,
            openReturn: openReturn, buyHoldReturn: buyHold
        )
    }

    private func sma(_ values: [Double], period: Int) -> [Double] {
        var result: [Double] = []
        var current: Double?
        for value in values {
            current = current.map { (value + Double(period - 1) * $0) / Double(period) } ?? value
            result.append(current!)
        }
        return result
    }

    private struct Lot {
        let date: String
        let name: String
        let price: Double
        var shares: Int
    }
}

private enum DashboardError: LocalizedError {
    case missingData
    case invalidURL
    case invalidPortfolio
    case cacheUnavailable
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingData: return "找不到内置看板数据文件。"
        case .invalidURL: return "无法构造数据服务地址。"
        case .invalidPortfolio: return "纸盘账户数据格式无效。"
        case .cacheUnavailable: return "本地缓存尚未初始化。"
        case .badResponse(let message): return message
        }
    }
}

private struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @State private var countdown = 10

    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = model.loadError {
                    NoticeView(text: error, color: Palette.up)
                } else if let data = model.data {
                    summary(data)
                    portfolioSection
                    liveSection
                    gmSection
                    accountCharts(data)
                    backtestSection(data)
                    strategiesSection(data)
                    timelineSection(data)
                    transactionsSection(data)
                    jobsSection(data)
                    footer(data)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(Palette.background)
        .task {
            await model.start()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                if !model.isQuoteRefreshPaused {
                    if countdown <= 1 {
                        countdown = 10
                        await model.refreshQuotes()
                    } else {
                        countdown -= 1
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                await model.refreshGM()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hermes 策略数据中心")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
            if let meta = model.data?.meta {
                Text("数据来源：\(meta.source) · 统计区间：\(meta.period) · 生成于 \(meta.generated)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.bottom, 4)
    }

    private func summary(_ data: DashboardData) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            MetricCard(title: "系统运行天数", value: "\(data.kpis.days)", detail: "自 2026-05-17")
            MetricCard(title: "定时任务累计执行", value: "\(data.kpis.total_runs) 次", detail: "\(data.jobs.count) 个 cron 作业")
            MetricCard(title: "纸盘累计收益", value: percent(data.kpis.nav.return_pct / 100), detail: "\(money(data.kpis.nav.current)) / 初始 \(money(data.kpis.nav.initial))", color: returnColor(data.kpis.nav.return_pct))
            MetricCard(title: "最大回撤", value: percent(data.kpis.nav.max_dd / 100), detail: "纸盘账户历史值", color: Palette.down)
            MetricCard(title: "纸盘胜率", value: percent(data.kpis.trades.win_rate / 100), detail: "\(data.kpis.trades.sells) 笔平仓 · 已实现 \(money(data.kpis.trades.realized))", color: Palette.down)
            MetricCard(title: "最佳单笔", value: percent(data.kpis.trades.best.pct / 100), detail: "\(data.kpis.trades.best.name) · \(money(data.kpis.trades.best.pnl))", color: Palette.up)
            MetricCard(title: "隔夜预测准确率", value: percent(data.kpis.overnight_acc.rate / 100), detail: "\(number(data.kpis.overnight_acc.hits))/\(number(data.kpis.overnight_acc.total)) 次验证", color: Palette.gold)
            MetricCard(title: "Demon Scout 胜率", value: percent(data.kpis.demon.rate / 100), detail: "\(data.kpis.demon.picks) 次选股 · \(money(data.kpis.demon.pnl))", color: Palette.up)
            MetricCard(title: "策略调优次数", value: "\(data.kpis.tunes)", detail: "完整调优记录")
        }
    }

    private var portfolioSection: some View {
        Group {
            if let portfolio = model.portfolio {
                SectionPanel(title: "📂 Hermes 纸盘账户") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        MetricCard(title: "可用现金", value: portfolio.cash.map(money) ?? "—")
                        MetricCard(title: "账户总值", value: portfolio.totalValue.map(money) ?? "—")
                        MetricCard(title: "持仓标的数", value: "\(portfolio.holdingCount)")
                        MetricCard(title: "账户更新时间", value: portfolio.updatedAt ?? "—")
                    }
                }
            } else if model.portfolioUnavailable {
                SectionPanel(title: "📂 Hermes 纸盘账户") {
                    Text("未找到 ~/.hermes/paper_trader/portfolio.json，账户数据不可用。")
                        .foregroundStyle(Palette.muted)
                        .font(.subheadline)
                }
            }
        }
    }

    private var liveSection: some View {
        SectionPanel(title: "📡 实时行情") {
            HStack(spacing: 14) {
                Text(model.lastQuoteUpdate.map { "上次更新时间 \(timeString($0))" } ?? "等待首次更新")
                    .foregroundStyle(Palette.muted)
                Text(model.isQuoteRefreshPaused ? "刷新已暂停" : "\(countdown) 秒后刷新")
                    .foregroundStyle(Palette.muted)
                Button(model.isQuoteRefreshPaused ? "▶ 继续刷新" : "⏸ 暂停刷新") {
                    model.isQuoteRefreshPaused.toggle()
                    if !model.isQuoteRefreshPaused {
                        countdown = 1
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            if let error = model.quoteError {
                NoticeView(text: "⚠️ \(error)（保留上次成功数据）", color: Palette.up)
            }
            if let error = model.cacheError {
                NoticeView(text: "⚠️ \(error)", color: Palette.gold)
            }
            if let location = model.cacheLocation {
                Text("本地数据缓存：\(location) · 行情快照 \(model.cachedQuoteSnapshotCount) 份 · 格林美日 K \(model.cachedGMBarCount) 条")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    QuoteHeader()
                    ForEach(model.watchedStocks) { stock in
                        QuoteRow(stock: stock, quote: model.quotes[stock.code])
                    }
                }
                .frame(minWidth: 840)
            }
        }
    }

    private var gmSection: some View {
        SectionPanel(title: "🌀 格林美 · RSI + KDJ 双超卖策略") {
            if let snapshot = model.gmSnapshot {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("交易规则").font(.headline)
                        Text("买入：RSI(6) < 16 且 J 值 < 10　·　卖出：WR(10) < 20 或 BR(26) 上穿 160")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                        Text("\(snapshot.state)：\(snapshot.signal)")
                            .font(.headline).foregroundStyle(snapshot.state == "买入关注" ? Palette.up : snapshot.state == "卖出关注" ? Palette.down : Palette.gold)
                        Text("行情日期 \(snapshot.date) · 收盘价 \(money(snapshot.close))")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("刷新策略") { Task { await model.refreshGM() } }
                        .buttonStyle(.bordered)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    MetricCard(title: "RSI(6)", value: number(snapshot.rsi), detail: "买入阈值 < 16", color: snapshot.rsi < 16 ? Palette.up : Palette.text)
                    MetricCard(title: "J 值 (9,3,3)", value: number(snapshot.j), detail: "买入阈值 < 10", color: snapshot.j < 10 ? Palette.up : Palette.text)
                    MetricCard(title: "WR(10)", value: number(snapshot.wr), detail: "卖出阈值 < 20", color: snapshot.wr < 20 ? Palette.down : Palette.text)
                    MetricCard(title: "BR(26)", value: number(snapshot.br), detail: "观察阈值 > 160", color: snapshot.br > 160 ? Palette.gold : Palette.text)
                }
                Text("RSI / J 值近 60 日走势").font(.headline).foregroundStyle(Palette.muted)
                Chart {
                    ForEach(snapshot.points) { point in
                        LineMark(x: .value("日期", point.date), y: .value("RSI", point.rsi))
                            .foregroundStyle(Palette.up).lineStyle(StrokeStyle(lineWidth: 2))
                        LineMark(x: .value("日期", point.date), y: .value("J 值", point.j))
                            .foregroundStyle(Palette.accent).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    RuleMark(y: .value("RSI 阈值", 16)).foregroundStyle(Palette.up.opacity(0.5)).lineStyle(StrokeStyle(dash: [5, 4]))
                    RuleMark(y: .value("J 阈值", 10)).foregroundStyle(Palette.accent.opacity(0.5)).lineStyle(StrokeStyle(dash: [5, 4]))
                }
                .chartLegend(position: .bottom)
                .frame(height: 220)
                gmTrades(snapshot)
            } else if let error = model.gmError {
                NoticeView(text: error, color: Palette.gold)
                Button("重试") { Task { await model.refreshGM() } }.buttonStyle(.bordered)
            } else {
                ProgressView("正在读取格林美日 K 数据…")
            }
        }
    }

    @ViewBuilder
    private func gmTrades(_ snapshot: GMSnapshot) -> some View {
        let wins = snapshot.trades.filter { $0.returnPct > 0 }
        let average = snapshot.trades.isEmpty ? nil : snapshot.trades.map(\.returnPct).reduce(0, +) / Double(snapshot.trades.count)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            MetricCard(title: "策略交易次数", value: "\(snapshot.trades.count)")
            MetricCard(title: "策略胜率", value: snapshot.trades.isEmpty ? "—" : percent(Double(wins.count) / Double(snapshot.trades.count)), color: wins.count * 2 >= snapshot.trades.count ? Palette.up : Palette.down)
            MetricCard(title: "平均收益 / 笔", value: average.map { percent($0 / 100) } ?? "—", color: returnColor(average))
            MetricCard(title: "买入持有对比", value: snapshot.buyHoldReturn.map { percent($0 / 100) } ?? "—", color: returnColor(snapshot.buyHoldReturn))
        }
        Text("格林美策略回测（2026-03-23 起；收盘确认、次日开盘执行）")
            .font(.headline).foregroundStyle(Palette.muted)
        if snapshot.trades.isEmpty && snapshot.openReturn == nil {
            Text("该区间内尚无已完成策略交易。").foregroundStyle(Palette.muted)
        } else {
            TableHeader(columns: ["买入日", "卖出日", "买入价", "卖出价", "持有交易日", "收益率", "离场原因"])
            ForEach(snapshot.trades) { trade in
                TableRow(columns: [
                    trade.entryDate, trade.exitDate, money(trade.entryPrice), money(trade.exitPrice),
                    "\(trade.holdingDays)", percent(trade.returnPct / 100), trade.exitReason
                ], color: returnColor(trade.returnPct))
            }
            if let floating = snapshot.openReturn {
                TableRow(columns: ["持仓中", "—", "—", "—", "—", percent(floating / 100), "浮动盈亏"], color: returnColor(floating))
            }
        }
    }

    private func accountCharts(_ data: DashboardData) -> some View {
        SectionPanel(title: "📊 纸盘模拟账户净值") {
            HStack(spacing: 10) {
                MetricCard(title: "初始资金", value: money(data.kpis.nav.initial))
                MetricCard(title: "当前净值", value: money(data.kpis.nav.current), color: returnColor(data.kpis.nav.return_pct))
                MetricCard(title: "累计平仓", value: "\(data.kpis.trades.sells) 笔")
            }
            Text("净值曲线（\(data.nav_series.first?.date ?? "") 起）")
                .font(.headline).foregroundStyle(Palette.muted)
            Chart(data.nav_series) { point in
                AreaMark(x: .value("日期", point.date), y: .value("净值", point.nav))
                    .foregroundStyle(Palette.accent.opacity(0.12))
                LineMark(x: .value("日期", point.date), y: .value("净值", point.nav))
                    .foregroundStyle(Palette.accent).lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { value in AxisValueLabel().foregroundStyle(Palette.muted) } }
            .chartYAxis { AxisMarks { value in AxisGridLine().foregroundStyle(Palette.border); AxisValueLabel().foregroundStyle(Palette.muted) } }
            .frame(height: 260)
            Text("交易盈亏分布").font(.headline).foregroundStyle(Palette.muted)
            Chart(data.transactions.filter { $0.action == "SELL" }.reversed()) { trade in
                BarMark(x: .value("盈亏", trade.pnl_pct ?? 0), y: .value("标的", trade.name))
                    .foregroundStyle((trade.pnl_pct ?? 0) >= 0 ? Palette.up : Palette.down)
                    .cornerRadius(3)
            }
            .chartXAxis { AxisMarks { value in AxisValueLabel().foregroundStyle(Palette.muted) } }
            .chartYAxis { AxisMarks { value in AxisValueLabel().foregroundStyle(Palette.muted) } }
            .frame(height: max(220, CGFloat(data.kpis.trades.sells) * 18))
        }
    }

    private func backtestSection(_ data: DashboardData) -> some View {
        SectionPanel(title: "🧪 指标回测") {
            HStack(alignment: .bottom, spacing: 12) {
                DatePicker("开始日期", selection: $model.backtestStart, displayedComponents: .date)
                DatePicker("结束日期", selection: $model.backtestEnd, displayedComponents: .date)
                Button("近 1 月") { model.setBacktestRange(months: 1) }.buttonStyle(.bordered)
                Button("近 3 月") { model.setBacktestRange(months: 3) }.buttonStyle(.bordered)
                Button("全区间") { model.setBacktestRange(months: nil) }.buttonStyle(.bordered)
                Button("运行回测") { model.runBacktest() }.buttonStyle(.borderedProminent)
            }
            .datePickerStyle(.field)
            if let error = model.backtestError { NoticeView(text: error, color: Palette.up) }
            if let report = model.backtestReport {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(report.metrics) { metric in
                        MetricCard(title: metric.title, value: metric.value, detail: metric.detail, color: metric.color)
                    }
                }
                Text("区间净值与回撤").font(.headline).foregroundStyle(Palette.muted)
                Chart {
                    ForEach(Array(report.nav.enumerated()), id: \.element.id) { index, point in
                        AreaMark(x: .value("日期", point.date), y: .value("净值", point.nav), series: .value("系列", "净值"))
                            .foregroundStyle(Palette.accent.opacity(0.12))
                        LineMark(x: .value("日期", point.date), y: .value("净值", point.nav), series: .value("系列", "净值"))
                            .foregroundStyle(Palette.accent)
                        AreaMark(x: .value("日期", point.date), y: .value("回撤", (report.drawdowns[index]) * 100), series: .value("系列", "回撤"))
                            .foregroundStyle(Palette.down.opacity(0.13))
                        LineMark(x: .value("日期", point.date), y: .value("回撤", (report.drawdowns[index]) * 100), series: .value("系列", "回撤"))
                            .foregroundStyle(Palette.down)
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 280)
                Text("三因子信号 FIFO 配对明细").font(.headline).foregroundStyle(Palette.muted)
                if report.pairs.isEmpty {
                    Text("区间内没有完整的买入/卖出配对。").foregroundStyle(Palette.muted)
                } else {
                    TableHeader(columns: ["买入日", "卖出日", "标的", "持有天数", "盈亏"])
                    ForEach(report.pairs) { pair in
                        TableRow(columns: [
                            pair.buyDate, pair.sellDate, "\(pair.name) (\(pair.code))",
                            "\(pair.holdingDays)", percent(pair.returnPct / 100)
                        ], color: returnColor(pair.returnPct))
                    }
                }
                Text("基准对照").font(.headline).foregroundStyle(Palette.muted)
                TableHeader(columns: ["基准", "区间收益", "说明"])
                TableRow(columns: ["持有现金", "0.0%", "基准收益为 0%"])
                TableRow(columns: ["平均持有期收益", report.averageHoldingReturn.map { percent($0 / 100) } ?? "—", "\(report.pairs.count) 笔 FIFO 配对等权平均"], color: returnColor(report.averageHoldingReturn))
            }
        }
    }

    private func strategiesSection(_ data: DashboardData) -> some View {
        SectionPanel(title: "🧠 策略与方法全景") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(data.strategies) { strategy in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(strategy.icon).font(.title2)
                            Text(strategy.name).font(.headline).foregroundStyle(Palette.text)
                            Spacer(minLength: 4)
                            Text(strategy.status).font(.caption).foregroundStyle(strategy.status.contains("运行") ? Palette.up : Palette.muted)
                        }
                        Text(strategy.desc).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        Text(strategy.method.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text("📌 \(strategy.perf)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.gold)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private func timelineSection(_ data: DashboardData) -> some View {
        SectionPanel(title: "🧬 策略演化时间线") {
            ForEach(data.timeline) { entry in
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(entry.date)  ·  \(entry.tag)").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                        Text(entry.title).font(.headline).foregroundStyle(Palette.text)
                        Text(entry.desc).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func transactionsSection(_ data: DashboardData) -> some View {
        SectionPanel(title: "交易记录") {
            TableHeader(columns: ["日期", "方向", "标的", "价格", "股数", "盈亏", "盈亏%", "触发原因"])
            ForEach(data.transactions) { trade in
                TableRow(columns: [
                    trade.date, trade.action == "BUY" ? "买入" : "卖出",
                    "\(trade.name) (\(trade.code))", money(trade.price), "\(trade.shares)",
                    trade.pnl.map(money) ?? "—",
                    trade.pnl_pct.map { percent($0 / 100) } ?? "—", trade.reason
                ], color: trade.action == "BUY" ? Palette.up : returnColor(trade.pnl))
            }
        }
    }

    private func jobsSection(_ data: DashboardData) -> some View {
        SectionPanel(title: "⚙️ 定时任务矩阵") {
            TableHeader(columns: ["任务", "调度", "累计运行", "状态"])
            ForEach(data.jobs) { job in
                TableRow(columns: [job.name, job.sched, "\(job.runs)", job.ok ? "● 正常" : "异常"], color: job.ok ? Palette.up : Palette.down)
            }
        }
    }

    private func footer(_ data: DashboardData) -> some View {
        Text("Hermes Strategy Dashboard · 数据截止 \(data.meta.period.components(separatedBy: " ~ ").last ?? data.meta.generated) · 涨红跌绿 · 仅供策略研究参考，不构成投资建议")
            .font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}

private struct SectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(Palette.text)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    var detail = ""
    var color = Palette.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(color).lineLimit(2).minimumScaleFactor(0.7)
            if !detail.isEmpty {
                Text(detail).font(.caption2).foregroundStyle(Palette.muted).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NoticeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

private struct QuoteHeader: View {
    var body: some View {
        TableRow(columns: ["名称", "代码", "现价", "涨跌幅", "涨跌额", "开盘", "最高", "最低"], isHeader: true)
    }
}

private struct QuoteRow: View {
    let stock: WatchedStock
    let quote: Quote?

    var body: some View {
        TableRow(columns: [
            quote?.name ?? stock.name,
            stock.code,
            quote.map { number($0.price) } ?? "—",
            quote.map { percent($0.changePct / 100) } ?? "—",
            quote.map { money($0.change) } ?? "—",
            quote?.open.map { number($0) } ?? "—",
            quote?.high.map { number($0) } ?? "—",
            quote?.low.map { number($0) } ?? "—"
        ], color: returnColor(quote?.changePct))
    }
}

private struct TableHeader: View {
    let columns: [String]
    var body: some View {
        TableRow(columns: columns, isHeader: true)
    }
}

private struct TableRow: View {
    let columns: [String]
    var isHeader = false
    var color = Palette.text

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(isHeader ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(isHeader ? Palette.muted : (index == columns.count - 1 && isHeader ? Palette.muted : color))
                    .frame(minWidth: index == 0 ? 90 : 75, maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 5)
            }
        }
        .background(isHeader ? Palette.panelAlt : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border.opacity(0.7)).frame(height: 0.5) }
    }
}

private func parseDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private func dateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeStyle = .medium
    formatter.dateStyle = .none
    return formatter.string(from: date)
}

private func money(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return "¥" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
}

private func number(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.locale(Locale(identifier: "zh_CN")).precision(.fractionLength(0...2)))
}

private func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return "\(value > 0 ? "+" : "")\(number(value * 100))%"
}

private func returnColor(_ value: Double?) -> Color {
    guard let value else { return Palette.text }
    return value > 0 ? Palette.up : value < 0 ? Palette.down : Palette.text
}

private func calendarDays(from start: String, to end: String) -> Int {
    guard let startDate = parseDate(start), let endDate = parseDate(end) else { return 0 }
    return Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day ?? 0
}

private func doubleValue(_ value: Any) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) }
    return nil
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
