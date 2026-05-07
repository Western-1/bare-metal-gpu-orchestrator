from locust import HttpUser, task, between, events
import json
import time

class EmbeddingUser(HttpUser):
    """
    Simulates users sending text embedding requests.
    """
    wait_time = between(0.1, 0.5)  # Wait 100-500ms between requests
    
    def on_start(self):
        """Called when a user starts."""
        self.client.verify = False  # Disable SSL verification for local testing
    
    @task(3)
    def embed_short_text(self):
        """Send short text for embedding (typical use case)."""
        payload = {
            "text": "This is a short sentence for embedding generation."
        }
        with self.client.post(
            "/embed",
            json=payload,
            catch_response=True,
            name="/embed (short)"
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    # Verify embedding vector is returned
                    if "embedding" not in data or len(data["embedding"]) != 384:
                        response.failure("Invalid embedding response")
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            else:
                response.failure(f"HTTP {response.status_code}")
    
    @task(1)
    def embed_long_text(self):
        """Send long text for embedding (stress test)."""
        payload = {
            "text": " ".join(["word"] * 500)  # 500 words
        }
        with self.client.post(
            "/embed",
            json=payload,
            catch_response=True,
            name="/embed (long)"
        ) as response:
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")
    
    @task
    def health_check(self):
        """Periodic health check."""
        with self.client.get("/health", catch_response=True, name="/health") as response:
            if response.status_code != 200:
                response.failure(f"Health check failed: HTTP {response.status_code}")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Called when the test starts."""
    print("\n" + "="*50)
    print("LOAD TEST STARTING")
    print("="*50)
    print(f"Target Users: {environment.runner.target_user_count if hasattr(environment.runner, 'target_user_count') else 'N/A'}")
    print(f"Spawn Rate: {environment.runner.spawn_rate if hasattr(environment.runner, 'spawn_rate') else 'N/A'}")
    print("="*50 + "\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Called when the test stops."""
    print("\n" + "="*50)
    print("LOAD TEST COMPLETED")
    print("="*50)
    if environment.stats.total.fail_ratio > 0.01:
        print(f"WARNING: Failure rate {environment.stats.total.fail_ratio:.2%} exceeds 1%")
    print(f"Total Requests: {environment.stats.total.num_requests}")
    print(f"Total Failures: {environment.stats.total.num_failures}")
    print(f"RPS: {environment.stats.total.total_rps:.2f}")
    print(f"P95 Latency: {environment.stats.total.get_response_time_percentile(0.95):.0f}ms")
    print("="*50 + "\n")
