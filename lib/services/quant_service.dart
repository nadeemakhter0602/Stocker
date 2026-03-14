import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/chart_data.dart';
import '../models/quant_models.dart';

// ─── Public API ──────────────────────────────────────────────────────────────

class QuantService {
  /// Runs Monte Carlo GBM simulation in a separate isolate.
  static Future<SimResult?> simulate(
      List<ChartPoint> pts, int horizonDays,
      {int lookbackDays = 252, bool useEwma = false}) async {
    if (pts.length < 30) return null;
    final closes = pts.map((p) => p.close).toList();
    return compute(
        _doSimulate,
        _SimInput(
            closes: closes,
            horizonDays: horizonDays,
            lookbackDays: lookbackDays,
            useEwma: useEwma));
  }

  /// Fits GARCH(1,1)-ARIMA(1,1,1): ARIMA mean + GARCH time-varying variance.
  static Future<GarchArimaResult?> garchArima(
      List<ChartPoint> pts, int horizonDays,
      {int lookbackDays = 252, bool useEwma = false}) async {
    if (pts.length < 30) return null;
    final closes = pts.map((p) => p.close).toList();
    return compute(
        _doGarchArima,
        _GarchArimaInput(
            closes: closes,
            horizonDays: horizonDays,
            lookbackDays: lookbackDays,
            useEwma: useEwma));
  }

  /// Fits ARIMA(1,1,1) via conditional least squares and returns price-level
  /// forecasts with 80 % and 95 % confidence intervals.
  static Future<ArimaResult?> arima(
      List<ChartPoint> pts, int horizonDays,
      {int lookbackDays = 252, bool useEwma = false}) async {
    if (pts.length < 30) return null;
    final closes = pts.map((p) => p.close).toList();
    return compute(
        _doArima,
        _ArimaInput(
            closes: closes,
            horizonDays: horizonDays,
            lookbackDays: lookbackDays,
            useEwma: useEwma));
  }
}

// ─── Isolate input ───────────────────────────────────────────────────────────

class _SimInput {
  final List<double> closes;
  final int horizonDays;
  final int lookbackDays;
  final bool useEwma;
  final int nSims;

  const _SimInput({
    required this.closes,
    required this.horizonDays,
    this.lookbackDays = 252,
    this.useEwma = false,
  }) : nSims = 10000;
}

// ─── Top-level isolate function ───────────────────────────────────────────────

SimResult _doSimulate(_SimInput input) {
  final allCloses = input.closes;
  final horizonDays = input.horizonDays;
  final nSims = input.nSims;

  // Slice to lookback window for parameter estimation; keep currentPrice from last bar
  final lb = input.lookbackDays;
  final estCloses = lb > 0 && allCloses.length > lb + 1
      ? allCloses.sublist(allCloses.length - lb - 1)
      : allCloses;

  // Log returns on estimation window
  final logReturns = <double>[];
  for (var i = 1; i < estCloses.length; i++) {
    logReturns.add(log(estCloses[i] / estCloses[i - 1]));
  }

  final n = logReturns.length;
  final muDaily = logReturns.reduce((a, b) => a + b) / n;
  final double sigmaDaily;
  if (input.useEwma) {
    sigmaDaily = _ewmaVol(logReturns);
  } else {
    final variance = logReturns
            .map((r) => (r - muDaily) * (r - muDaily))
            .reduce((a, b) => a + b) /
        (n - 1);
    sigmaDaily = sqrt(variance);
  }
  final closes = allCloses;
  // GBM drift term
  final drift = muDaily - 0.5 * sigmaDaily * sigmaDaily;
  final currentPrice = closes.last;

  final rng = Random();

  // Box-Muller normal random
  double gauss() {
    final u1 = rng.nextDouble().clamp(1e-10, 1.0);
    final u2 = rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  // Memory-efficient simulation: keep one price array per step,
  // sort a copy to extract percentiles, then advance.
  var prices = List<double>.filled(nSims, currentPrice);

  final p5 = <double>[currentPrice];
  final p25 = <double>[currentPrice];
  final p50 = <double>[currentPrice];
  final p75 = <double>[currentPrice];
  final p95 = <double>[currentPrice];

  for (var d = 0; d < horizonDays; d++) {
    final next = List<double>.generate(
        nSims, (s) => prices[s] * exp(drift + sigmaDaily * gauss()));
    final sorted = List<double>.from(next)..sort();
    p5.add(_pct(sorted, 5));
    p25.add(_pct(sorted, 25));
    p50.add(_pct(sorted, 50));
    p75.add(_pct(sorted, 75));
    p95.add(_pct(sorted, 95));
    prices = next;
  }

  final probProfit =
      prices.where((p) => p > currentPrice).length / nSims;

  return SimResult(
    p5: p5,
    p25: p25,
    p50: p50,
    p75: p75,
    p95: p95,
    currentPrice: currentPrice,
    horizonDays: horizonDays,
    probProfit: probProfit,
    stats: _computeStats(closes, logReturns, sigmaDaily, muDaily),
  );
}

// ─── EWMA volatility (RiskMetrics λ=0.94) ────────────────────────────────────

double _ewmaVol(List<double> returns, {double lambda = 0.94}) {
  if (returns.isEmpty) return 0.0;
  // seed with first squared return
  double var2 = returns[0] * returns[0];
  for (var i = 1; i < returns.length; i++) {
    var2 = lambda * var2 + (1 - lambda) * returns[i] * returns[i];
  }
  return sqrt(var2);
}

// ─── Percentile helper ────────────────────────────────────────────────────────

double _pct(List<double> sorted, double pct) {
  final idx = (pct / 100) * (sorted.length - 1);
  final lo = idx.floor();
  final hi = idx.ceil();
  if (lo == hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
}

// ─── Risk metrics ─────────────────────────────────────────────────────────────

QuantStats _computeStats(List<double> closes, List<double> logReturns,
    double sigmaDaily, double muDaily) {
  const rf = 0.05; // annualised risk-free rate
  final annVol = sigmaDaily * sqrt(252);
  final annReturn = muDaily * 252;

  // Sharpe
  final sharpe = annVol == 0 ? 0.0 : (annReturn - rf) / annVol;

  // Sortino — downside deviation (returns < 0)
  final downside = logReturns.where((r) => r < 0).toList();
  final downsideVar = downside.isEmpty
      ? sigmaDaily * sigmaDaily
      : downside.map((r) => r * r).reduce((a, b) => a + b) /
          logReturns.length;
  final downsideStd = sqrt(downsideVar * 252);
  final sortino =
      downsideStd == 0 ? 0.0 : (annReturn - rf) / downsideStd;

  // Max drawdown (full history)
  double peak = closes[0];
  double maxDD = 0.0;
  for (final p in closes) {
    if (p > peak) peak = p;
    final dd = (peak - p) / peak;
    if (dd > maxDD) maxDD = dd;
  }

  // Current drawdown from most recent all-time high
  double curPeak = closes[0];
  for (final p in closes) {
    if (p > curPeak) curPeak = p;
  }
  final curDD = curPeak == 0 ? 0.0 : (curPeak - closes.last) / curPeak;

  // Historical VaR (non-parametric)
  final sortedRet = List<double>.from(logReturns)..sort();
  final price = closes.last;
  final var95 = -_pct(sortedRet, 5) * price;
  final var99 = -_pct(sortedRet, 1) * price;

  // CVaR / Expected Shortfall at 95 %
  final cutoff = _pct(sortedRet, 5);
  final tail = sortedRet.where((r) => r <= cutoff).toList();
  final cvar95 = tail.isEmpty
      ? var95
      : -(tail.reduce((a, b) => a + b) / tail.length) * price;

  // Kelly Criterion (quarter-Kelly for safety)
  final wins = logReturns.where((r) => r > 0).toList();
  final losses = logReturns.where((r) => r < 0).toList();
  double kelly = 0.0;
  if (wins.isNotEmpty && losses.isNotEmpty) {
    final winRate = wins.length / logReturns.length;
    final avgWin = wins.reduce((a, b) => a + b) / wins.length;
    final avgLoss =
        losses.map((r) => r.abs()).reduce((a, b) => a + b) / losses.length;
    if (avgLoss > 0 && avgWin > 0) {
      kelly = (winRate / avgLoss - (1 - winRate) / avgWin)
              .clamp(0.0, 1.0) *
          0.25;
    }
  }

  return QuantStats(
    annualizedVol: annVol,
    sharpeRatio: sharpe,
    sortinoRatio: sortino,
    maxDrawdown: maxDD,
    currentDrawdown: curDD,
    var95: var95,
    var99: var99,
    cvar95: cvar95,
    kellyFraction: kelly,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ARIMA(1,1,1)
// ═══════════════════════════════════════════════════════════════════════════

class _ArimaInput {
  final List<double> closes;
  final int horizonDays;
  final int lookbackDays;
  final bool useEwma;
  const _ArimaInput({
    required this.closes,
    required this.horizonDays,
    this.lookbackDays = 252,
    this.useEwma = false,
  });
}

ArimaResult _doArima(_ArimaInput input) {
  final allCloses = input.closes;
  final h = input.horizonDays;

  // Slice to lookback window for parameter estimation
  final lb = input.lookbackDays;
  final estCloses = lb > 0 && allCloses.length > lb + 1
      ? allCloses.sublist(allCloses.length - lb - 1)
      : allCloses;

  // Log returns (the differenced series) on estimation window
  final returns = <double>[];
  for (var i = 1; i < estCloses.length; i++) {
    returns.add(log(estCloses[i] / estCloses[i - 1]));
  }

  final mu = returns.reduce((a, b) => a + b) / returns.length;
  // Demeaned returns for parameter estimation
  final dm = returns.map((r) => r - mu).toList();

  // ── Two-stage grid search for φ and θ ─────────────────────────────────
  // Stage 1: coarse 20×20
  double bestPhi = 0, bestTheta = 0;
  double bestCSS = double.infinity;
  const coarse = 20;
  for (var pi = 0; pi < coarse; pi++) {
    final phi = -0.95 + pi * 1.9 / (coarse - 1);
    for (var ti = 0; ti < coarse; ti++) {
      final theta = -0.95 + ti * 1.9 / (coarse - 1);
      final css = _css111(dm, phi, theta);
      if (css < bestCSS) {
        bestCSS = css;
        bestPhi = phi;
        bestTheta = theta;
      }
    }
  }
  // Stage 2: fine 11×11 around best coarse point
  final step = 1.9 / (coarse - 1);
  for (var pi = -5; pi <= 5; pi++) {
    final phi = (bestPhi + pi * step / 10).clamp(-0.99, 0.99);
    for (var ti = -5; ti <= 5; ti++) {
      final theta = (bestTheta + ti * step / 10).clamp(-0.99, 0.99);
      final css = _css111(dm, phi, theta);
      if (css < bestCSS) {
        bestCSS = css;
        bestPhi = phi;
        bestTheta = theta;
      }
    }
  }

  // ── Residuals and σ ───────────────────────────────────────────────────
  final resid = _residuals111(dm, bestPhi, bestTheta);
  final double sigma;
  if (input.useEwma) {
    sigma = _ewmaVol(resid);
  } else {
    final sigma2 =
        resid.map((e) => e * e).reduce((a, b) => a + b) / (dm.length - 2);
    sigma = sqrt(sigma2);
  }

  // ── MA(∞) ψ coefficients for forecast variance ───────────────────────
  // ψ₀=1, ψ₁=φ+θ, ψₖ=φ·ψₖ₋₁ for k≥2
  final psi = List<double>.filled(h + 1, 0.0);
  psi[0] = 1.0;
  if (h >= 1) psi[1] = bestPhi + bestTheta;
  for (var k = 2; k <= h; k++) {
    psi[k] = bestPhi * psi[k - 1];
  }

  // Cumulative ψ sums: Ψₖ = Σⱼ₌₀ᵏ ψⱼ
  final bigPsi = List<double>.filled(h + 1, 0.0);
  double cumPsi = 0;
  for (var k = 0; k <= h; k++) {
    cumPsi += psi[k];
    bigPsi[k] = cumPsi;
  }

  // Cumulative forecast variance of Σy_{T+k}:
  // Var = σ² · Σₖ₌₀ʰ⁻¹ Ψₖ²
  final cumVar = List<double>.filled(h, 0.0);
  double runVar = 0;
  for (var k = 0; k < h; k++) {
    runVar += sigma * sigma * bigPsi[k] * bigPsi[k];
    cumVar[k] = runVar;
  }

  // ── Point forecast of log returns ─────────────────────────────────────
  // 1-step: ŷ_{T+1} = μ + φ·dm_T + θ·ε_T
  // h-step: ŷ_{T+h} = μ + φ^(h-1)·(φ·dm_T + θ·ε_T)
  final lastDm = dm.last;
  final lastEps = resid.last;
  final forecastBase = bestPhi * lastDm + bestTheta * lastEps;

  // Cumulative mean log return at each horizon step
  final cumMean = List<double>.filled(h, 0.0);
  double runMean = 0;
  for (var k = 0; k < h; k++) {
    final stepForecast = mu + (k == 0 ? forecastBase : pow(bestPhi, k).toDouble() * forecastBase);
    runMean += stepForecast;
    cumMean[k] = runMean;
  }

  // ── Convert to price levels with CIs ─────────────────────────────────
  final currentPrice = allCloses.last;
  final forecast = <double>[currentPrice];
  final ci80Lo = <double>[currentPrice];
  final ci80Hi = <double>[currentPrice];
  final ci95Lo = <double>[currentPrice];
  final ci95Hi = <double>[currentPrice];

  for (var k = 0; k < h; k++) {
    final m = cumMean[k];
    final s = sqrt(cumVar[k]);
    forecast.add(currentPrice * exp(m));
    ci80Lo.add(currentPrice * exp(m - 1.282 * s));
    ci80Hi.add(currentPrice * exp(m + 1.282 * s));
    ci95Lo.add(currentPrice * exp(m - 1.960 * s));
    ci95Hi.add(currentPrice * exp(m + 1.960 * s));
  }

  // P(price_h > price_0) = Φ(cumMean[h-1] / sqrt(cumVar[h-1]))
  final finalVar = cumVar[h - 1];
  final probProfit = finalVar > 0
      ? _normalCdf(cumMean[h - 1] / sqrt(finalVar))
      : (cumMean[h - 1] >= 0 ? 1.0 : 0.0);

  return ArimaResult(
    forecast: forecast,
    ci80Lower: ci80Lo,
    ci80Upper: ci80Hi,
    ci95Lower: ci95Lo,
    ci95Upper: ci95Hi,
    phi: bestPhi,
    theta: bestTheta,
    sigma: sigma,
    probProfit: probProfit,
    horizonDays: h,
  );
}

// Standard normal CDF via Abramowitz & Stegun approximation (max error 7.5e-8).
double _normalCdf(double x) {
  const a1 =  0.254829592;
  const a2 = -0.284496736;
  const a3 =  1.421413741;
  const a4 = -1.453152027;
  const a5 =  1.061405429;
  const p  =  0.3275911;
  final sign = x < 0 ? -1 : 1;
  final t = 1.0 / (1.0 + p * x.abs());
  final y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x);
  return 0.5 * (1.0 + sign * y);
}

// Conditional Sum of Squares for ARIMA(1,1,1) on demeaned series.
double _css111(List<double> dm, double phi, double theta) {
  double css = 0, prevEps = 0;
  for (var t = 1; t < dm.length; t++) {
    final eps = dm[t] - phi * dm[t - 1] - theta * prevEps;
    css += eps * eps;
    prevEps = eps;
  }
  return css;
}

// Compute full residual sequence at estimated (phi, theta).
List<double> _residuals111(List<double> dm, double phi, double theta) {
  final out = <double>[0.0];
  double prevEps = 0;
  for (var t = 1; t < dm.length; t++) {
    final eps = dm[t] - phi * dm[t - 1] - theta * prevEps;
    out.add(eps);
    prevEps = eps;
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// GARCH(1,1)-ARIMA(1,1,1)
// Mean equation: ARIMA(1,1,1) on log-returns (same fitting as above).
// Variance equation: GARCH(1,1) fitted to ARIMA residuals via grid-search MLE.
// ═══════════════════════════════════════════════════════════════════════════

class _GarchArimaInput {
  final List<double> closes;
  final int horizonDays;
  final int lookbackDays;
  final bool useEwma;
  const _GarchArimaInput({
    required this.closes,
    required this.horizonDays,
    this.lookbackDays = 252,
    this.useEwma = false,
  });
}

GarchArimaResult _doGarchArima(_GarchArimaInput input) {
  final allCloses = input.closes;
  final h = input.horizonDays;

  // Slice to lookback window
  final lb = input.lookbackDays;
  final estCloses = lb > 0 && allCloses.length > lb + 1
      ? allCloses.sublist(allCloses.length - lb - 1)
      : allCloses;

  // Log returns (differenced series)
  final returns = <double>[];
  for (var i = 1; i < estCloses.length; i++) {
    returns.add(log(estCloses[i] / estCloses[i - 1]));
  }
  final mu = returns.reduce((a, b) => a + b) / returns.length;
  final dm = returns.map((r) => r - mu).toList();

  // Step 1: Fit ARIMA(1,1,1) via two-stage CSS grid search (same as _doArima)
  double bestPhi = 0, bestTheta = 0;
  double bestCSS = double.infinity;
  const coarse = 20;
  for (var pi = 0; pi < coarse; pi++) {
    final phi = -0.95 + pi * 1.9 / (coarse - 1);
    for (var ti = 0; ti < coarse; ti++) {
      final theta = -0.95 + ti * 1.9 / (coarse - 1);
      final css = _css111(dm, phi, theta);
      if (css < bestCSS) {
        bestCSS = css;
        bestPhi = phi;
        bestTheta = theta;
      }
    }
  }
  final step = 1.9 / (coarse - 1);
  for (var pi = -5; pi <= 5; pi++) {
    final phi = (bestPhi + pi * step / 10).clamp(-0.99, 0.99);
    for (var ti = -5; ti <= 5; ti++) {
      final theta = (bestTheta + ti * step / 10).clamp(-0.99, 0.99);
      final css = _css111(dm, phi, theta);
      if (css < bestCSS) {
        bestCSS = css;
        bestPhi = phi;
        bestTheta = theta;
      }
    }
  }

  // ARIMA residuals
  final resid = _residuals111(dm, bestPhi, bestTheta);

  // Step 2: Fit GARCH(1,1) to ARIMA residuals via grid-search MLE
  final (:alpha, :beta, :omega) = _fitGarch11(resid);

  // Step 3: Reconstruct conditional variance series to get h_T (last in-sample)
  final uncondVar =
      resid.map((e) => e * e).reduce((a, b) => a + b) / resid.length;
  double hPrev = uncondVar;
  for (var t = 1; t < resid.length; t++) {
    hPrev = omega + alpha * resid[t - 1] * resid[t - 1] + beta * hPrev;
  }

  // Step 4: Forward GARCH variances h_{T+1}, ..., h_{T+h}
  final fwdH = List<double>.filled(h, 0.0);
  fwdH[0] = omega + alpha * resid.last * resid.last + beta * hPrev;
  for (var k = 1; k < h; k++) {
    fwdH[k] = omega + (alpha + beta) * fwdH[k - 1];
  }

  // Step 5: MA(∞) ψ coefficients and cumulative Ψ (same as ARIMA)
  final psi = List<double>.filled(h + 1, 0.0);
  psi[0] = 1.0;
  if (h >= 1) psi[1] = bestPhi + bestTheta;
  for (var k = 2; k <= h; k++) {
    psi[k] = bestPhi * psi[k - 1];
  }
  final bigPsi = List<double>.filled(h + 1, 0.0);
  double cumPsi = 0;
  for (var k = 0; k <= h; k++) {
    cumPsi += psi[k];
    bigPsi[k] = cumPsi;
  }

  // Cumulative forecast variance using time-varying GARCH h instead of const σ²
  // Var[k] = Σ_{j=0}^{k} Ψ_j² · h_{T+j+1}
  final cumVar = List<double>.filled(h, 0.0);
  double runVar = 0;
  for (var k = 0; k < h; k++) {
    runVar += bigPsi[k] * bigPsi[k] * fwdH[k];
    cumVar[k] = runVar;
  }

  // Point forecast (same ARIMA mean)
  final lastDm = dm.last;
  final lastEps = resid.last;
  final forecastBase = bestPhi * lastDm + bestTheta * lastEps;
  final cumMean = List<double>.filled(h, 0.0);
  double runMean = 0;
  for (var k = 0; k < h; k++) {
    final stepForecast =
        mu + (k == 0 ? forecastBase : pow(bestPhi, k).toDouble() * forecastBase);
    runMean += stepForecast;
    cumMean[k] = runMean;
  }

  // Price-level forecasts and CIs
  final currentPrice = allCloses.last;
  final forecast = <double>[currentPrice];
  final ci80Lo = <double>[currentPrice];
  final ci80Hi = <double>[currentPrice];
  final ci95Lo = <double>[currentPrice];
  final ci95Hi = <double>[currentPrice];
  for (var k = 0; k < h; k++) {
    final m = cumMean[k];
    final s = sqrt(cumVar[k]);
    forecast.add(currentPrice * exp(m));
    ci80Lo.add(currentPrice * exp(m - 1.282 * s));
    ci80Hi.add(currentPrice * exp(m + 1.282 * s));
    ci95Lo.add(currentPrice * exp(m - 1.960 * s));
    ci95Hi.add(currentPrice * exp(m + 1.960 * s));
  }

  // Annualised conditional vol per step
  final condVol = fwdH.map((hk) => sqrt(hk * 252)).toList();

  // Probability of profit
  final finalVar = cumVar[h - 1];
  final probProfit = finalVar > 0
      ? _normalCdf(cumMean[h - 1] / sqrt(finalVar))
      : (cumMean[h - 1] >= 0 ? 1.0 : 0.0);

  return GarchArimaResult(
    forecast: forecast,
    ci80Lower: ci80Lo,
    ci80Upper: ci80Hi,
    ci95Lower: ci95Lo,
    ci95Upper: ci95Hi,
    condVol: condVol,
    phi: bestPhi,
    theta: bestTheta,
    omega: omega,
    alpha: alpha,
    beta: beta,
    probProfit: probProfit,
    horizonDays: h,
  );
}

// Fit GARCH(1,1) to a residual series via 2D grid-search MLE.
({double alpha, double beta, double omega}) _fitGarch11(List<double> resid) {
  final uncondVar =
      resid.map((e) => e * e).reduce((a, b) => a + b) / resid.length;

  double bestAlpha = 0.05, bestBeta = 0.90;
  double bestLL = double.negativeInfinity;

  const alphas = [0.02, 0.05, 0.08, 0.12, 0.16, 0.20, 0.25, 0.30];
  const betas = [0.50, 0.60, 0.70, 0.75, 0.80, 0.85, 0.88, 0.91, 0.94, 0.97];

  for (final a in alphas) {
    for (final b in betas) {
      if (a + b >= 0.999) continue;
      final w = uncondVar * (1 - a - b);
      final ll = _garchLogLik(resid, w, a, b, uncondVar);
      if (ll > bestLL) {
        bestLL = ll;
        bestAlpha = a;
        bestBeta = b;
      }
    }
  }

  // Fine refinement: ±3 steps of 0.01 around coarse best
  for (var ai = -3; ai <= 3; ai++) {
    for (var bi = -3; bi <= 3; bi++) {
      final a = (bestAlpha + ai * 0.01).clamp(0.001, 0.499);
      final b = (bestBeta + bi * 0.01).clamp(0.001, 0.998);
      if (a + b >= 0.999) continue;
      final w = uncondVar * (1 - a - b);
      final ll = _garchLogLik(resid, w, a, b, uncondVar);
      if (ll > bestLL) {
        bestLL = ll;
        bestAlpha = a;
        bestBeta = b;
      }
    }
  }

  return (
    alpha: bestAlpha,
    beta: bestBeta,
    omega: uncondVar * (1 - bestAlpha - bestBeta),
  );
}

// GARCH(1,1) Gaussian log-likelihood (up to constant).
double _garchLogLik(
    List<double> resid, double omega, double alpha, double beta, double h0) {
  double h = h0;
  double ll = 0;
  for (var t = 1; t < resid.length; t++) {
    h = omega + alpha * resid[t - 1] * resid[t - 1] + beta * h;
    if (h <= 0) return double.negativeInfinity;
    ll -= 0.5 * (log(h) + resid[t] * resid[t] / h);
  }
  return ll;
}
