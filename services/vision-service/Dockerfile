FROM devops-ai-base:latest

WORKDIR /app

# Copy source code
COPY main.py .

# Run as non-root user for security
RUN useradd -m -u 1000 api_user
USER api_user

EXPOSE 8001

# Start server
CMD ["python3", "main.py"]
