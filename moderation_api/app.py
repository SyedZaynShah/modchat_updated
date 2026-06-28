"""
ModChat — Message Moderation Inference API
==========================================

A tiny FastAPI server that loads the fine-tuned HuggingFace text-classification
model (the `moderation_model` folder you trained: config.json, model.safetensors,
tokenizer.json, tokenizer_config.json) and exposes a single endpoint the Flutter
app calls before sending a GROUP message.

    POST /predict   { "text": "..." }  ->  { "label": "...", "blocked": true/false, ... }

If the predicted label is anything other than "normal", `blocked` is true and the
Flutter app refuses to send the message and tells the sender why.

Run:
    pip install -r requirements.txt
    uvicorn app:app --host 0.0.0.0 --port 8000

Put the 4 model files inside  ./model  (see model/README.txt).
"""

import os
import functools

import torch
import torch.nn.functional as F
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from transformers import AutoModelForSequenceClassification, AutoTokenizer

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

# Folder that contains config.json / model.safetensors / tokenizer files.
MODEL_DIR = os.environ.get("MODEL_DIR", os.path.join(os.path.dirname(__file__), "model"))

# A message is allowed ONLY if the predicted label is one of these (case-insensitive).
# Everything else (abusive / swear / threat / ...) is blocked.
NORMAL_LABELS = {
    s.strip().lower()
    for s in os.environ.get("NORMAL_LABELS", "normal,neutral,clean,none,ok,non-abusive,not_abusive").split(",")
    if s.strip()
}

# OPTIONAL override for the label order if your model's config.json stores generic
# names like "LABEL_0". Comma-separated, in index order. Example:
#   LABELS="normal,abusive,swear,threat"
LABELS_OVERRIDE = [s.strip() for s in os.environ.get("LABELS", "").split(",") if s.strip()]

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


# --------------------------------------------------------------------------- #
# Model loading (lazy + cached so startup is fast and import never crashes)
# --------------------------------------------------------------------------- #

@functools.lru_cache(maxsize=1)
def _load():
    if not os.path.isdir(MODEL_DIR) or not os.path.exists(os.path.join(MODEL_DIR, "config.json")):
        raise RuntimeError(
            f"Model not found in '{MODEL_DIR}'. Place config.json, model.safetensors, "
            f"tokenizer.json and tokenizer_config.json there. See model/README.txt."
        )

    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    model = AutoModelForSequenceClassification.from_pretrained(MODEL_DIR)
    model.to(DEVICE)
    model.eval()

    # Resolve human-readable labels.
    id2label = dict(model.config.id2label)  # e.g. {0: "LABEL_0", ...} or {0: "normal", ...}
    generic = all(str(v).lower().startswith("label_") for v in id2label.values())
    if LABELS_OVERRIDE:
        labels = {i: LABELS_OVERRIDE[i] for i in range(len(LABELS_OVERRIDE))}
    elif generic:
        # Model didn't ship real names. Best-effort default — VERIFY this matches
        # how you trained it, or set the LABELS env var.
        default = ["normal", "abusive", "swear", "threat"]
        labels = {i: (default[i] if i < len(default) else f"label_{i}") for i in id2label}
    else:
        labels = id2label

    return tokenizer, model, labels


# --------------------------------------------------------------------------- #
# FastAPI app
# --------------------------------------------------------------------------- #

app = FastAPI(title="ModChat Moderation API", version="1.0.0")

# Allow the Flutter web/desktop build (and any device) to call us in development.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class PredictIn(BaseModel):
    text: str


class PredictOut(BaseModel):
    label: str
    blocked: bool
    confidence: float
    scores: dict


@app.get("/health")
def health():
    """Liveness probe. Also reports whether the model loaded successfully."""
    try:
        _, _, labels = _load()
        return {"status": "ok", "device": DEVICE, "labels": list(labels.values())}
    except Exception as e:  # noqa: BLE001
        return {"status": "model_not_loaded", "error": str(e)}


@app.get("/labels")
def labels():
    """Returns the label set in index order so you can verify the mapping."""
    _, _, labels = _load()
    return {"labels": labels, "normal_labels": sorted(NORMAL_LABELS)}


@app.post("/predict", response_model=PredictOut)
def predict(body: PredictIn):
    tokenizer, model, labels = _load()

    text = (body.text or "").strip()
    if not text:
        # Empty text is never "abusive" — let the client handle empties.
        return PredictOut(label="normal", blocked=False, confidence=1.0, scores={})

    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        max_length=256,
        padding=True,
    ).to(DEVICE)

    with torch.no_grad():
        logits = model(**inputs).logits
        probs = F.softmax(logits, dim=-1)[0]

    scores = {labels[i]: float(probs[i]) for i in range(len(probs))}
    top_idx = int(torch.argmax(probs).item())
    top_label = labels[top_idx]
    blocked = top_label.strip().lower() not in NORMAL_LABELS

    return PredictOut(
        label=top_label,
        blocked=blocked,
        confidence=float(probs[top_idx]),
        scores=scores,
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
