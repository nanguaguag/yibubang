FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py policy.py ./
CMD exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080}
