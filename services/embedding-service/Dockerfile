FROM nvidia/cuda:12.1.0-base-ubuntu22.04

# Install python and pip
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy source code
COPY main.py .

# Run as non-root user for security
RUN useradd -m -u 1000 api_user
USER api_user

EXPOSE 8000

# Start server
CMD ["python3", "main.py"]
