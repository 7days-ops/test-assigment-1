# Stage 1
FROM python:3.11-alpine AS builder

WORKDIR /app


RUN apk add --no-cache --virtual .build-deps \
    gcc \
    musl-dev \
    postgresql-dev


COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install --prefer-binary -r requirements.txt

# Stage 2
FROM python:3.11-alpine

WORKDIR /app


RUN apk add --no-cache libpq


COPY --from=builder /install /usr/local


COPY . .


RUN adduser -D -u 1000 appuser && chown -R appuser:appuser /app
USER appuser


EXPOSE 5000


ENV FLASK_ENV=production \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1


CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "2", "--worker-class", "gthread", "--timeout", "30", "main:app"]
