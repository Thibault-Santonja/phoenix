# Rate Limiting Telemetry Metrics

This document describes the telemetry metrics available for monitoring rate limiting in the Portfolio application.

## Overview

The Portfolio application emits telemetry events for all rate limit checks, allowing you to monitor:
- How many requests are being rate limited
- Which endpoints are most frequently rate limited
- Performance of rate limit checks
- Remaining capacity for different actions

## Events

### `[:portfolio, :rate_limiter, :check]`

Emitted every time a rate limit check is performed.

**Measurements:**
- `duration` (integer, native time unit): Time taken to perform the rate limit check

**Metadata:**
- `action` (atom): The action being rate limited (`:magic_link_request`, `:login_attempt`, etc.)
- `identifier` (string): The identifier being checked (IP address, email, etc.)
- `result` (atom): Either `:allow` or `:deny`
- `remaining` (integer | nil): Number of remaining requests (only present when result is `:allow`)
- `retry_after_ms` (integer | nil): Milliseconds until next allowed request (only present when result is `:deny`)

**Example handler:**

```elixir
:telemetry.attach(
  "my-rate-limiter-handler",
  [:portfolio, :rate_limiter, :check],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata})
  end,
  nil
)
```

## Metrics

The following metrics are defined in `PortfolioWeb.Telemetry` and can be exported to monitoring systems like Prometheus, StatsD, or DataDog.

### Counter Metrics

#### `portfolio.rate_limiter.check.count`

Total number of rate limit checks performed.

- **Type:** Counter
- **Tags:** `action`, `result`
- **Use cases:**
  - Track rate limiting activity over time
  - Alert on sudden spikes in rate limit violations
  - Monitor specific actions separately

**Example queries:**
```promql
# Total rate limit checks
rate(portfolio_rate_limiter_check_count[5m])

# Rate limit denials per action
rate(portfolio_rate_limiter_check_count{result="deny"}[5m])

# Rate limit denial rate
rate(portfolio_rate_limiter_check_count{result="deny"}[5m]) 
  / rate(portfolio_rate_limiter_check_count[5m])
```

#### `portfolio.rate_limiter.allowed.count`

Number of requests that were allowed (not rate limited).

- **Type:** Counter
- **Tags:** `action`

#### `portfolio.rate_limiter.denied.count`

Number of requests that were denied (rate limited).

- **Type:** Counter
- **Tags:** `action`
- **Use cases:**
  - Track abuse patterns
  - Alert on sustained attack attempts
  - Identify which actions are most abused

### Distribution Metrics

#### `portfolio.rate_limiter.check.duration`

Distribution of rate limit check durations.

- **Type:** Distribution
- **Unit:** Milliseconds
- **Tags:** `action`
- **Use cases:**
  - Monitor performance of rate limiting
  - Detect performance degradation
  - Optimize rate limiting backend (Hammer/Redis)

**Example queries:**
```promql
# 95th percentile of rate limit check duration
histogram_quantile(0.95, 
  rate(portfolio_rate_limiter_check_duration_bucket[5m]))

# Average duration by action
rate(portfolio_rate_limiter_check_duration_sum[5m]) 
  / rate(portfolio_rate_limiter_check_duration_count[5m])
```

### Summary Metrics

#### `portfolio.rate_limiter.remaining.value`

Summary of remaining request capacity.

- **Type:** Summary
- **Unit:** Count
- **Tags:** `action`
- **Use cases:**
  - Monitor system capacity utilization
  - Predict when rate limits will be hit
  - Identify legitimate high-volume users

#### `portfolio.rate_limiter.retry_after.value`

Summary of retry-after times when requests are denied.

- **Type:** Summary  
- **Unit:** Milliseconds
- **Tags:** `action`
- **Use cases:**
  - Monitor how long users must wait
  - Tune rate limit windows
  - Identify overly aggressive rate limiting

## Actions

The following actions are currently rate limited:

| Action | Limit | Period | Purpose |
|--------|-------|--------|---------|
| `:magic_link_request` | 5 | 1 hour | Prevent email spam |
| `:magic_link_verify` | 10 | 5 minutes | Prevent token brute force |
| `:login_attempt` | 10 | 1 hour | Prevent credential stuffing |

## Integration Examples

### Prometheus + Grafana

Export metrics using `TelemetryMetricsPrometheus`:

```elixir
# In mix.exs
{:telemetry_metrics_prometheus, "~> 1.1"}

# In application.ex
{TelemetryMetricsPrometheus,
  metrics: PortfolioWeb.Telemetry.metrics(),
  port: 9568}
```

**Sample Grafana dashboard:**

```json
{
  "panels": [
    {
      "title": "Rate Limit Violations",
      "targets": [
        {
          "expr": "rate(portfolio_rate_limiter_denied_count[5m])"
        }
      ]
    },
    {
      "title": "Rate Limit Check Duration p95",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, rate(portfolio_rate_limiter_check_duration_bucket[5m]))"
        }
      ]
    }
  ]
}
```

### StatsD

Export metrics using `TelemetryMetricsStatsd`:

```elixir
# In mix.exs
{:telemetry_metrics_statsd, "~> 0.6"}

# In application.ex
{TelemetryMetricsStatsd,
  metrics: PortfolioWeb.Telemetry.metrics(),
  host: "statsd.example.com",
  port: 8125}
```

### DataDog

Export metrics using DataDog's DogStatsD:

```elixir
# In mix.exs
{:telemetry_metrics_statsd, "~> 0.6"}

# In application.ex
{TelemetryMetricsStatsd,
  metrics: PortfolioWeb.Telemetry.metrics(),
  host: "localhost",
  port: 8125,
  global_tags: [env: Mix.env()]}
```

### Custom Logger

Simple logging of rate limit events:

```elixir
# In application.ex or telemetry.ex
:telemetry.attach(
  "rate-limit-logger",
  [:portfolio, :rate_limiter, :check],
  fn _event, _measurements, metadata, _config ->
    if metadata.result == :deny do
      Logger.warning("Rate limit exceeded",
        action: metadata.action,
        identifier: metadata.identifier
      )
    end
  end,
  nil
)
```

## Monitoring Best Practices

### Alerts

Set up alerts for rate limiting anomalies:

**High rate limit violation rate:**
```yaml
alert: HighRateLimitViolations
expr: |
  rate(portfolio_rate_limiter_denied_count[5m]) > 10
for: 5m
labels:
  severity: warning
annotations:
  summary: "High rate of rate limit violations detected"
```

**Sustained attack attempt:**
```yaml
alert: SustainedRateLimitAttack
expr: |
  rate(portfolio_rate_limiter_denied_count{action="magic_link_request"}[5m]) > 50
for: 15m
labels:
  severity: critical
annotations:
  summary: "Sustained rate limit attack on magic link requests"
```

**Rate limiting performance degradation:**
```yaml
alert: RateLimitingSlowdown
expr: |
  histogram_quantile(0.95, 
    rate(portfolio_rate_limiter_check_duration_bucket[5m])
  ) > 100
for: 10m
labels:
  severity: warning
annotations:
  summary: "Rate limit checks taking longer than expected"
```

### Dashboards

Create dashboards to visualize:

1. **Overview Dashboard**
   - Total rate limit checks (allowed vs denied)
   - Denial rate by action
   - Top identifiers by violations

2. **Performance Dashboard**
   - Rate limit check duration (p50, p95, p99)
   - Throughput (checks per second)
   - Remaining capacity distribution

3. **Security Dashboard**
   - Failed attempts over time
   - Geographic distribution of denials (if using IP geolocation)
   - Top offending IPs/emails

### Log Analysis

Combine with structured logging for deeper analysis:

```elixir
# Logs include action, identifier, and result
# Example log entry:
# [warning] Rate limit check: denied action: magic_link_request identifier: 192.168.1.100 retry_after_seconds: 3600 duration_ms: 2
```

Use log aggregation tools (ELK stack, Loki, etc.) to:
- Identify attack patterns
- Correlate with application events
- Create custom visualizations

## Testing

Test telemetry events in your test suite:

```elixir
test "emits telemetry event on rate limit" do
  ref = :telemetry_test.attach_event_handlers(
    self(), 
    [[:portfolio, :rate_limiter, :check]]
  )

  RateLimiter.check_rate(:magic_link_request, "test@example.com")

  assert_receive {[:portfolio, :rate_limiter, :check], ^ref, measurements, metadata}
  assert measurements.duration > 0
  assert metadata.action == :magic_link_request
  assert metadata.result in [:allow, :deny]
end
```

## Performance Considerations

Rate limit checks are designed to be fast:
- Typical duration: < 5ms
- Backend: Hammer with ETS (in-memory)
- Network overhead: None (local checks)

Telemetry overhead is minimal:
- Event emission: < 1ms
- No blocking operations
- Asynchronous metric collection

## Troubleshooting

### High check durations

If rate limit checks are slow (> 50ms):

1. Check Hammer backend configuration
2. Verify ETS table size (`:ets.info(:hammer_ets_backend)`)
3. Consider Redis backend for distributed setup
4. Check for ETS table locks

### Missing metrics

If metrics aren't appearing:

1. Verify telemetry handlers are attached:
   ```elixir
   :telemetry.list_handlers([:portfolio, :rate_limiter, :check])
   ```

2. Check metric exporter configuration
3. Verify metrics are defined in `PortfolioWeb.Telemetry.metrics/0`
4. Check exporter logs for errors

### Incorrect counts

If counts don't match expectations:

1. Check for multiple application instances (distributed counting)
2. Verify metric type (counter vs gauge)
3. Check rate limit reset intervals
4. Verify time windows in queries

## References

- [Telemetry Documentation](https://hexdocs.pm/telemetry/)
- [Telemetry Metrics](https://hexdocs.pm/telemetry_metrics/)
- [Portfolio ADR 023: Rate Limiting](../adr/023_rate_limiting.md)
- [Hammer Documentation](https://hexdocs.pm/hammer/)

## Changelog

- **2025-11-13**: Initial telemetry implementation for rate limiting
  - Added `[:portfolio, :rate_limiter, :check]` event
  - Defined 6 metrics for monitoring
  - Integrated with existing telemetry infrastructure

Last updated: 2025-11-13
