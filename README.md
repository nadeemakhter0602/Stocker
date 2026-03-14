# Stocker

A Flutter stock and ETF tracker with real-time quotes, interactive charts, and on-device quantitative analysis — no API key required.

## Features

### Quotes & Search
- Search any stock, ETF, or mutual fund globally (US, India, LSE, and more)
- Real-time price, change, and change % from Yahoo Finance
- Persistent watchlist saved on-device with `shared_preferences`
- Market cap, volume, P/E ratio, 52-week high/low in the Overview tab

### Charts
- Line chart with **1W / 1M / 1Y / Max** interval chips
- Change % updates dynamically based on the selected interval
- Max interval fetches full weekly history for long-term view

### Forecast Tab (on-device, no server)
Three independent models run in background isolates via `compute()`:

| Model | Description |
|-------|-------------|
| **Monte Carlo GBM** | 10,000 Geometric Brownian Motion paths, 7-day horizon. Outputs P5/P25/P50/P75/P95 fan chart. |
| **ARIMA(1,1,1)** | Fitted via two-stage conditional least-squares grid search. Outputs point forecast + 80%/95% CIs. |
| **GARCH(1,1)-ARIMA** | ARIMA mean equation + GARCH(1,1) variance equation fitted by grid-search MLE. Time-varying confidence bands that widen/narrow with recent volatility. |

All three show a **probability of gain** for the 7-day horizon.

Configurable lookback window: **1Y / 2Y / 5Y / Max**
Optional **EWMA σ** (RiskMetrics λ = 0.94) instead of historical volatility.

### Risk Metrics
Computed from historical returns alongside GBM:
- Annualised volatility, Sharpe ratio, Sortino ratio
- Max drawdown and current drawdown from all-time high
- Historical VaR 95% / 99% and CVaR (Expected Shortfall) 95%
- Kelly Criterion position sizing (¼ Kelly)

### Technical Tab
Key price statistics and market data in a clean card layout.

### News Tab
Stock-specific news via Google News RSS, filtered by company name. Falls back to Yahoo Finance search if RSS is unavailable.

## Tech Stack

- **Flutter** + **Material 3** (dark navy theme, teal-green accent)
- **Provider** for state management
- **fl_chart** for line charts
- **Custom `CustomPainter`** for forecast fan charts
- **Yahoo Finance** unofficial API (no key required)
- **Google News RSS** for stock news

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.11

### Run

```bash
flutter pub get
flutter run
```

Runs on Android, iOS, macOS, Linux, and Windows.

### Build (Android)

```bash
flutter build apk --release
```

## Project Structure

```
lib/
├── main.dart
├── models/          # StockQuote, ChartPoint, SearchResult, NewsItem, quant_models
├── services/        # YahooFinanceService, WatchlistService, QuantService
├── providers/       # SearchProvider, QuoteProvider, WatchlistProvider
├── screens/         # HomeScreen, SearchScreen, WatchlistScreen, StockDetailScreen
├── widgets/         # PriceChart, ForecastChart, StatCard, ChangeBadge, ...
└── theme/           # AppTheme, ThemeProvider
```

## Data Sources

All data is fetched at runtime with no API key:

| Source | Used for |
|--------|----------|
| `query1.finance.yahoo.com/v8/finance/chart` | Quotes and chart OHLCV data |
| `query1.finance.yahoo.com/v1/finance/search` | Symbol search |
| `news.google.com/rss/search` | Stock news (primary) |
| Yahoo Finance search `newsCount` | Stock news (fallback) |

> Yahoo Finance's unofficial API is rate-limited and may occasionally return errors. The app surfaces these gracefully with a retry prompt.

## Disclaimer

Forecasts are for educational purposes only. GBM assumes log-normal returns and constant volatility. ARIMA assumes linear autocorrelation in log-returns. GARCH-ARIMA models volatility clustering but assumes Gaussian errors. None account for jumps, fat tails, or regime changes. **Not financial advice.**

## License

MIT
