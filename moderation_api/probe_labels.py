"""
Probe the model to discover which output index corresponds to which class.

Because config.json only has generic LABEL_0..LABEL_3, we feed obvious examples
of each category and print the argmax index + full score vector. From the output
you can read off the mapping, e.g. "normal -> index 1", and then start the server
with the right order:  $env:LABELS = "abusive,normal,swear,threat"
"""

import os
import torch
import torch.nn.functional as F
from transformers import AutoModelForSequenceClassification, AutoTokenizer

MODEL_DIR = os.path.join(os.path.dirname(__file__), "model")

tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
model = AutoModelForSequenceClassification.from_pretrained(MODEL_DIR)
model.eval()

samples = {
    "normal":  ["hello, how are you doing today?", "let's meet at 5pm for the project", "thanks so much, that helps a lot"],
    "abusive": ["you are a complete idiot and a loser", "shut up you stupid moron", "nobody likes you, you are worthless"],
    "swear":   ["what the fuck is this shit", "this is fucking bullshit", "damn that asshole"],
    "threat":  ["i will kill you", "i am going to find you and hurt you", "you are dead, i will beat you up"],
}

num_labels = model.config.num_labels
print(f"\nModel has {num_labels} labels.\n" + "=" * 60)

tally = {expected: [0] * num_labels for expected in samples}

for expected, texts in samples.items():
    print(f"\n### Expected category: {expected.upper()}")
    for t in texts:
        inputs = tokenizer(t, return_tensors="pt", truncation=True, max_length=256)
        with torch.no_grad():
            probs = F.softmax(model(**inputs).logits, dim=-1)[0]
        idx = int(torch.argmax(probs))
        tally[expected][idx] += 1
        scores = ", ".join(f"{i}:{probs[i]:.2f}" for i in range(num_labels))
        print(f"  idx={idx}  [{scores}]  <- {t!r}")

print("\n" + "=" * 60)
print("BEST-GUESS MAPPING (most frequent winning index per category):")
guess = {}
for expected, counts in tally.items():
    best_idx = max(range(num_labels), key=lambda i: counts[i])
    guess[best_idx] = expected
    print(f"  index {best_idx}  ->  {expected}   (votes: {counts})")

ordered = [guess.get(i, f"label_{i}") for i in range(num_labels)]
print("\nIf each category mapped to a distinct index, start the server with:")
print(f'  $env:LABELS = "{",".join(ordered)}"')
print("=" * 60)
