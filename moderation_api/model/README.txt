PLACE YOUR TRAINED MODEL FILES IN THIS FOLDER
=============================================

Copy the contents of the `moderation_model` folder from your Google Drive into
THIS directory so it ends up looking like:

    moderation_api/
      model/
        config.json
        model.safetensors
        tokenizer_config.json
        tokenizer.json
        (any other tokenizer files like special_tokens_map.json, vocab.txt are fine too)

That's it — the server reads everything from here on startup.

IMPORTANT — verify the label order:
After starting the server, open  http://127.0.0.1:8000/labels  in a browser.
Make sure the labels read like {0: "normal", 1: "abusive", 2: "swear", 3: "threat"}
(or whatever order you trained with). If they show up as "LABEL_0", "LABEL_1", ...,
start the server with the correct order, e.g. (PowerShell):

    $env:LABELS = "normal,abusive,swear,threat"
    uvicorn app:app --host 0.0.0.0 --port 8000
