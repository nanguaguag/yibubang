FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py policy.py retrieval.py textbook_support.py answer_models.py builtin_answer.py textbook_catalog.json answer_model_catalog.json ./
CMD exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080}
