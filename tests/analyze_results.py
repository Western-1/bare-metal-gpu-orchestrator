import pandas as pd


def analyze_locust_results(csv_file):
    """Analyze Locust test results from CSV file."""
    df = pd.read_csv(csv_file)

    # Calculate statistics
    stats = {
        "total_requests": len(df),
        "failures": df["Failure"].sum(),
        "failure_rate": df["Failure"].mean() * 100,
        "avg_latency": df["Average Response Time"].mean(),
        "p50_latency": df["Average Response Time"].median(),
        "p95_latency": df["Average Response Time"].quantile(0.95),
        "p99_latency": df["Average Response Time"].quantile(0.99),
        "min_latency": df["Average Response Time"].min(),
        "max_latency": df["Average Response Time"].max(),
        "rps": df["Request Count"].sum() / (df["Time"].max() - df["Time"].min()),
    }

    # Print statistics
    print("\n" + "=" * 50)
    print("LOAD TEST RESULTS")
    print("=" * 50)
    print(f"Total Requests: {stats['total_requests']}")
    print(f"Failures: {stats['failures']} ({stats['failure_rate']:.2f}%)")
    print(f"RPS: {stats['rps']:.2f}")
    print(f"Average Latency: {stats['avg_latency']:.0f}ms")
    print(f"P50 Latency: {stats['p50_latency']:.0f}ms")
    print(f"P95 Latency: {stats['p95_latency']:.0f}ms")
    print(f"P99 Latency: {stats['p99_latency']:.0f}ms")
    print(f"Min Latency: {stats['min_latency']:.0f}ms")
    print(f"Max Latency: {stats['max_latency']:.0f}ms")
    print("=" * 50 + "\n")

    # Check success criteria
    print("SUCCESS CRITERIA CHECK:")
    print(
        f"P95 Latency < 200ms: {'✓ PASS' if stats['p95_latency'] < 200 else '✗ FAIL'}"
    )
    print(f"Failure Rate < 1%: {'✓ PASS' if stats['failure_rate'] < 1 else '✗ FAIL'}")
    print("=" * 50 + "\n")

    return stats


if __name__ == "__main__":
    analyze_locust_results("sustained_embedding_stats_stats.csv")
