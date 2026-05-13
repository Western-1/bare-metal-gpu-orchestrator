from locust import HttpUser, task, between, events
import base64


class VisionUser(HttpUser):
    wait_time = between(0.5, 1.0)

    SAMPLE_IMAGE = base64.b64encode(
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01"
        b"\x00\x00\x05\x00\x01\x0d\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
    ).decode("utf-8")

    def on_start(self):
        self.client.verify = False

    @task(3)
    def classify_image(self):
        payload = {"image": self.SAMPLE_IMAGE}
        with self.client.post(
            "/classify", json=payload, catch_response=True, name="/classify"
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    if "category" not in data or "confidence" not in data:
                        response.failure("Invalid classification response")
                except Exception:
                    response.failure("Invalid response format")
            else:
                response.failure(f"HTTP {response.status_code}")

    @task
    def health_check(self):
        with self.client.get(
            "/health", catch_response=True, name="/health"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Health check failed: HTTP {response.status_code}")


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, exception, **kwargs):
    if response_time > 1000:
        print(f"SLOW REQUEST: {name} took {response_time:.0f}ms")
