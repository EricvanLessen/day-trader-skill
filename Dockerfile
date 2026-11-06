FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TRADER_DATA_DIR=/data

WORKDIR /app
COPY requirements-monitor.txt .
RUN pip install --no-cache-dir -r requirements-monitor.txt \
    && useradd --create-home --uid 10001 trader \
    && mkdir /data && chown trader:trader /data

COPY --chown=trader:trader . /app
USER trader
EXPOSE 8080
CMD ["uvicorn", "ops.web.app:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
