FROM python:3.12-alpine3.22 AS builder

WORKDIR /build
COPY main.py .
RUN python3 -m compileall -b .

FROM python:3.12-alpine3.22 AS runtime

RUN apk upgrade --no-cache && \
    addgroup -g 10001 appgroup && \
    adduser -u 10001 -G appgroup -s /sbin/nologin -D appuser

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /build/main.py /app/main.py

USER appuser:appgroup

ENV PORT=8080 \
    PYTHONUNBUFFERED=1

EXPOSE 8080

ENTRYPOINT ["python3", "/app/main.py"]
