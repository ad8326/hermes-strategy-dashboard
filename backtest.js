(function () {
  const source = typeof DATA === 'undefined' ? null : DATA;
  if (!source) {
    throw new Error('回测数据未加载：请先加载 data.js');
  }

  const DataStore = {
    filterByRange(start, end) {
      const inRange = date => date >= start && date <= end;
      return {
        start,
        end,
        nav_series: source.nav_series.filter(point => inRange(point.date)),
        transactions: source.transactions.filter(transaction => inRange(transaction.date)),
        strategies: source.strategies,
        kpis: source.kpis
      };
    }
  };

  const Backtester = {
    run(start, end) {
      const range = DataStore.filterByRange(start, end);
      const nav = range.nav_series;
      const values = nav.map(point => point.nav);
      const dailyReturns = [];

      for (let index = 1; index < values.length; index += 1) {
        if (values[index - 1] !== 0) {
          dailyReturns.push(values[index] / values[index - 1] - 1);
        }
      }

      const cumulativeReturn = values.length > 1 && values[0] !== 0
        ? values[values.length - 1] / values[0] - 1
        : (values.length ? 0 : null);
      const annualizedReturn = values.length > 1 && values[0] > 0 && values[values.length - 1] > 0
        ? Math.pow(values[values.length - 1] / values[0], 252 / (values.length - 1)) - 1
        : null;
      const meanDailyReturn = dailyReturns.length
        ? dailyReturns.reduce((sum, value) => sum + value, 0) / dailyReturns.length
        : null;
      const dailyVariance = dailyReturns.length
        ? dailyReturns.reduce((sum, value) => sum + Math.pow(value - meanDailyReturn, 2), 0) / dailyReturns.length
        : null;
      const dailyVolatility = dailyVariance === null ? null : Math.sqrt(dailyVariance);
      const annualizedVolatility = dailyVolatility === null ? null : dailyVolatility * Math.sqrt(252);
      const dailyRiskFreeRate = 0.015 / 252;
      const sharpeRatio = dailyVolatility
        ? ((meanDailyReturn - dailyRiskFreeRate) / dailyVolatility) * Math.sqrt(252)
        : null;

      let peak = null;
      let maxDrawdown = 0;
      let drawdownStart = null;
      let drawdownEnd = null;
      const drawdowns = nav.map(point => {
        if (peak === null || point.nav > peak.nav) peak = point;
        const drawdown = peak.nav === 0 ? 0 : point.nav / peak.nav - 1;
        if (drawdown < maxDrawdown) {
          maxDrawdown = drawdown;
          drawdownStart = peak.date;
          drawdownEnd = point.date;
        }
        return drawdown;
      });

      const sells = range.transactions.filter(transaction => transaction.action === 'SELL');
      const wins = sells.filter(transaction => transaction.pnl_pct > 0);
      const losses = sells.filter(transaction => transaction.pnl_pct < 0);
      const averageWin = wins.length
        ? wins.reduce((sum, transaction) => sum + transaction.pnl_pct, 0) / wins.length
        : null;
      const averageLoss = losses.length
        ? losses.reduce((sum, transaction) => sum + transaction.pnl_pct, 0) / losses.length
        : null;
      // 最佳/最差按盈亏百分比口径（与看板 KPI 一致），金额仅作参考
      const bestTrade = sells.reduce((best, transaction) =>
        !best || transaction.pnl_pct > best.pnl_pct ? transaction : best, null);
      const worstTrade = sells.reduce((worst, transaction) =>
        !worst || transaction.pnl_pct < worst.pnl_pct ? transaction : worst, null);
      const realizedPnl = sells.reduce((sum, transaction) => sum + (transaction.pnl || 0), 0);

      const pairedTrades = this.pairTrades(range.transactions);
      const averageHoldingReturn = pairedTrades.length
        ? pairedTrades.reduce((sum, trade) => sum + trade.returnPct, 0) / pairedTrades.length
        : null;
      const averageHoldingDays = pairedTrades.length
        ? pairedTrades.reduce((sum, trade) => sum + trade.holdingDays, 0) / pairedTrades.length
        : null;

      const totalTradingDays = source.nav_series.length;
      const dayRatio = totalTradingDays ? nav.length / totalTradingDays : 0;
      const overnightHits = range.kpis.overnight_acc.hits * dayRatio;
      const overnightTotal = range.kpis.overnight_acc.total * dayRatio;

      return {
        range,
        nav: {
          cumulativeReturn,
          annualizedReturn,
          maxDrawdown,
          drawdownStart,
          drawdownEnd,
          drawdowns,
          annualizedVolatility,
          sharpeRatio,
          calmarRatio: maxDrawdown < 0 && annualizedReturn !== null
            ? annualizedReturn / Math.abs(maxDrawdown)
            : null,
          profitableDayRatio: dailyReturns.length
            ? dailyReturns.filter(value => value > 0).length / dailyReturns.length
            : null
        },
        trades: {
          count: sells.length,
          winRate: sells.length ? wins.length / sells.length : null,
          averageWin,
          averageLoss,
          winLossRatio: averageWin !== null && averageLoss !== null && averageLoss !== 0
            ? averageWin / Math.abs(averageLoss)
            : null,
          realizedPnl,
          bestTrade,
          worstTrade
        },
        overnight: {
          accuracy: overnightTotal ? overnightHits / overnightTotal : null,
          estimatedHits: overnightHits,
          estimatedTotal: overnightTotal
        },
        pairedTrades,
        benchmarks: {
          cashReturn: 0,
          averageHoldingReturn
        },
        averageHoldingDays
      };
    },

    pairTrades(transactions) {
      const queues = new Map();
      const pairs = [];
      const ordered = transactions
        .map((transaction, index) => ({ transaction, index }))
        .sort((left, right) =>
          left.transaction.date.localeCompare(right.transaction.date) || left.index - right.index);

      ordered.forEach(({ transaction }) => {
        if (transaction.action === 'BUY') {
          if (!queues.has(transaction.code)) queues.set(transaction.code, []);
          queues.get(transaction.code).push({
            date: transaction.date,
            name: transaction.name,
            price: transaction.price,
            shares: transaction.shares
          });
          return;
        }
        if (transaction.action !== 'SELL') return;

        const queue = queues.get(transaction.code);
        let remainingShares = transaction.shares;
        while (queue && queue.length && remainingShares > 0) {
          const lot = queue[0];
          const matchedShares = Math.min(remainingShares, lot.shares);
          const holdingDays = Math.max(
            0,
            (Date.parse(`${transaction.date}T00:00:00Z`) - Date.parse(`${lot.date}T00:00:00Z`)) / 86400000
          );
          pairs.push({
            buyDate: lot.date,
            sellDate: transaction.date,
            name: transaction.name || lot.name,
            code: transaction.code,
            shares: matchedShares,
            holdingDays,
            returnPct: lot.price ? (transaction.price / lot.price - 1) * 100 : 0
          });
          lot.shares -= matchedShares;
          remainingShares -= matchedShares;
          if (lot.shares <= 0) queue.shift();
        }
      });

      return pairs;
    }
  };

  globalThis.DataStore = DataStore;
  globalThis.Backtester = Backtester;
})();
