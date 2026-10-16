FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY *.py schema.sql ./
RUN useradd --uid 10001 app && mkdir -p /data/uploads && chown app /data/uploads
USER app
EXPOSE 8080
HEALTHCHECK CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"
CMD ["gunicorn", "-b", "0.0.0.0:8080", "-w", "2", "app:app"]
