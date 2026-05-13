from locust import HttpUser, task, between


class MultiServiceUser(HttpUser):
    """
    Simulates users accessing both embedding and vision services.
    """

    wait_time = between(0.2, 0.8)

    # Service endpoints
    embedding_host = "http://embedding-service.ml-workloads.svc.cluster.local:8000"
    vision_host = "http://vision-service.ml-workloads.svc.cluster.local:8001"

    def on_start(self):
        """Called when a user starts."""
        self.client.verify = False

    @task(2)
    def embed_request(self):
        """Send embedding request."""
        payload = {"text": "Test sentence for embedding."}
        with self.client.post(
            "/embed",
            json=payload,
            catch_response=True,
            name="/embed",
            host=self.embedding_host,
        ) as response:
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")

    @task(1)
    def vision_request(self):
        """Send vision request."""
        # Use minimal image for testing
        payload = {"image": "base64_encoded_image_placeholder"}
        with self.client.post(
            "/classify",
            json=payload,
            catch_response=True,
            name="/classify",
            host=self.vision_host,
        ) as response:
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")
