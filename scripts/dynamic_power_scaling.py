import subprocess
import time


def get_gpu_utilization():
    """Get current GPU utilization."""
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader"],
        capture_output=True,
        text=True,
    )
    return int(result.stdout.strip())


def set_power_limit(watts):
    """Set GPU power limit."""
    subprocess.run(["sudo", "nvidia-smi", "-pl", str(watts)])


def dynamic_power_scaling():
    """Adjust power limit based on utilization."""
    while True:
        util = get_gpu_utilization()

        if util > 80:
            # High utilization: increase power
            set_power_limit(250)
        elif util > 50:
            # Medium utilization: balanced power
            set_power_limit(220)
        else:
            # Low utilization: eco power
            set_power_limit(180)

        time.sleep(60)  # Check every minute


if __name__ == "__main__":
    dynamic_power_scaling()
