# ModChat Moderation API

A small [FastAPI](https://fastapi.tiangolo.com/) server that runs your trained
HuggingFace text-classification model. The Flutter app calls it **before sending a
group message**: if the model labels the text as `abusive`, `swear`, or `threat`,
the message is **not** sent and the sender is told why. `normal` messages go through.

```
Flutter (group send)  ──POST /predict {text}──▶  this server  ──▶  { label, blocked }
```

## Quick start (scripts)

On Windows you can skip the manual steps below and just run, from inside this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1   # one-time: creates .venv + installs deps
powershell -ExecutionPolicy Bypass -File .\run.ps1      # starts the server on :8000
```

`setup.ps1` also tells you if any model files are still missing. The manual steps
below are the same thing, spelled out.

## 1. Put the model in place

Copy your `moderation_model` files into [`model/`](model/) so it contains:

```
model/config.json
model/model.safetensors
model/tokenizer_config.json
model/tokenizer.json
```

## 2. Install dependencies

```powershell
cd moderation_api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

> `torch` is a large download (~hundreds of MB). First install takes a while.

## 3. Run the server

```powershell
uvicorn app:app --host 0.0.0.0 --port 8000
```

Leave this running. Quick checks in a browser / curl:

- `http://127.0.0.1:8000/health` → should say `"status": "ok"` and list your labels.
- `http://127.0.0.1:8000/labels` → **verify** the label order is correct (see below).

Test a prediction:

```powershell
curl -X POST http://127.0.0.1:8000/predict -H "Content-Type: application/json" -d "{\"text\":\"I will kill you\"}"
```

## 4. Verify the label mapping (important)

The server reads label names from your model's `config.json`. If they show up as
`LABEL_0`, `LABEL_1`, … instead of real names, tell the server the correct order:

```powershell
$env:LABELS = "normal,abusive,swear,threat"   # use YOUR training order
uvicorn app:app --host 0.0.0.0 --port 8000
```

By default a message is **allowed** only if its label is one of:
`normal, neutral, clean, none, ok, non-abusive, not_abusive` (case-insensitive).
Everything else is blocked. Override with the `NORMAL_LABELS` env var if needed.

## 5. Point the Flutter app at this server

In the project root [`.env`](../.env), set `MODERATION_API_URL`:

| Where the Flutter app runs        | Use this URL                       |
| --------------------------------- | ---------------------------------- |
| Chrome / Edge / Windows desktop   | `http://127.0.0.1:8000`            |
| Android **emulator**              | `http://10.0.2.2:8000`             |
| Physical phone (same Wi-Fi)       | `http://<YOUR-PC-LAN-IP>:8000`     |

Then restart the Flutter app so it reloads `.env`.

## Endpoints

| Method | Path       | Body            | Returns                                             |
| ------ | ---------- | --------------- | --------------------------------------------------- |
| GET    | `/health`  | –               | `{status, device, labels}`                          |
| GET    | `/labels`  | –               | `{labels, normal_labels}`                           |
| POST   | `/predict` | `{ "text": …}`  | `{ label, blocked, confidence, scores }`            |
