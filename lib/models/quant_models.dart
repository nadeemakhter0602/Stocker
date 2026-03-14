class QuantStats {
  final double annualizedVol; // e.g. 0.243 = 24.3 %
  final double sharpeRatio;
  final double sortinoRatio;
  final double maxDrawdown; // 0.35 = 35 %
  final double currentDrawdown; // drawdown from last peak
  final double var95; // 1-day dollar VaR at 95 %
  final double var99; // 1-day dollar VaR at 99 %
  final double cvar95; // Expected Shortfall (CVaR) at 95 %
  final double kellyFraction; // quarter-Kelly optimal bet size

  const QuantStats({
    required this.annualizedVol,
    required this.sharpeRatio,
    required this.sortinoRatio,
    required this.maxDrawdown,
    required this.currentDrawdown,
    required this.var95,
    required this.var99,
    required this.cvar95,
    required this.kellyFraction,
  });
}

/// ARIMA(1,1,1) forecast result.
/// All band arrays: length = horizonDays + 1, index 0 = currentPrice (today).
class ArimaResult {
  final List<double> forecast;  // point forecast (median)
  final List<double> ci80Lower, ci80Upper; // 80 % confidence interval
  final List<double> ci95Lower, ci95Upper; // 95 % confidence interval
  final double phi;        // estimated AR(1) coefficient
  final double theta;      // estimated MA(1) coefficient
  final double sigma;      // residual std dev (daily log-return units)
  final double probProfit; // P(price_7d > price_0) from normal distribution
  final int horizonDays;

  const ArimaResult({
    required this.forecast,
    required this.ci80Lower,
    required this.ci80Upper,
    required this.ci95Lower,
    required this.ci95Upper,
    required this.phi,
    required this.theta,
    required this.sigma,
    required this.probProfit,
    required this.horizonDays,
  });
}

/// GARCH(1,1)-ARIMA(1,1,1) forecast result.
/// Mean equation = ARIMA(1,1,1); Variance equation = GARCH(1,1).
/// All band arrays: length = horizonDays + 1, index 0 = currentPrice (today).
class GarchArimaResult {
  final List<double> forecast;
  final List<double> ci80Lower, ci80Upper;
  final List<double> ci95Lower, ci95Upper;
  final List<double> condVol; // length = horizonDays, annualised GARCH vol per step
  final double phi;    // ARIMA AR(1) coefficient
  final double theta;  // ARIMA MA(1) coefficient
  final double omega;  // GARCH long-run variance weight
  final double alpha;  // GARCH ARCH coefficient
  final double beta;   // GARCH GARCH coefficient
  final double probProfit;
  final int horizonDays;

  const GarchArimaResult({
    required this.forecast,
    required this.ci80Lower,
    required this.ci80Upper,
    required this.ci95Lower,
    required this.ci95Upper,
    required this.condVol,
    required this.phi,
    required this.theta,
    required this.omega,
    required this.alpha,
    required this.beta,
    required this.probProfit,
    required this.horizonDays,
  });
}

class SimResult {
  /// Band arrays: length = horizonDays + 1, index 0 = currentPrice (today).
  final List<double> p5, p25, p50, p75, p95;
  final double currentPrice;
  final int horizonDays;
  final double probProfit; // fraction of sims ending above currentPrice
  final QuantStats stats;

  const SimResult({
    required this.p5,
    required this.p25,
    required this.p50,
    required this.p75,
    required this.p95,
    required this.currentPrice,
    required this.horizonDays,
    required this.probProfit,
    required this.stats,
  });
}
