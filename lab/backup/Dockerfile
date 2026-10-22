FROM postgres:16
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-boto3 \
    && rm -rf /var/lib/apt/lists/*
COPY backup.py /opt/backup.py
ENTRYPOINT ["python3", "/opt/backup.py"]
