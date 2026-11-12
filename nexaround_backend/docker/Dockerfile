FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Free map data (Overture downloads, used only by the openimport container).
# Its own layer so the big requirements layer above stays cached; httpfs is
# installed at build time so nothing is downloaded when an import runs.
COPY requirements-opendata.txt .
RUN pip install --no-cache-dir -r requirements-opendata.txt \
 && python -c "import duckdb; duckdb.connect().execute('INSTALL httpfs')"

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
