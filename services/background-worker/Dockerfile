FROM devops-ai-base:latest

WORKDIR /app

# Copy source code
COPY main.py .

# Run as non-root user for security
RUN useradd -m -u 1000 api_user
USER api_user

CMD ["python3", "-u", "main.py"]
