# Deploy: Wed May 20 06:29:35 PM UTC 2026
from fastapi import FastAPI, UploadFile, File, HTTPException
from google.cloud import speech, bigquery, storage
from datetime import datetime, timezone
import subprocess, os, json

app = FastAPI()
BUCKET = os.environ.get("BUCKET", "").replace("gs://", "")

@app.get("/")
def root():
    return {"status": "VoiceInsights ON"}

@app.post("/transkrybuj")
async def transkrybuj(plik: UploadFile = File(...), jezyk: str = "pl-PL"):
    if not plik.filename.lower().endswith(".wav"):
        raise HTTPException(
            status_code=400,
            detail=f"Nieobsługiwany format '{plik.filename}'. Dozwolone tylko .wav"
        )
        return {"error: Nieobsługiwany format '{plik.filename}'. Dozwolone tylko .wav"}

    tmp = f"/tmp/{plik.filename}"
    mono = f"/tmp/mono_{plik.filename}"

    with open(tmp, "wb") as f:
        f.write(await plik.read())

    subprocess.run(["ffmpeg", "-i", tmp, "-ac", "1", mono, "-y", "-loglevel", "quiet"])
    try:
        result = subprocess.run([
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", mono
        ], capture_output=True, text=True)
        dlugosc = float(json.loads(result.stdout)["format"]["duration"])
    except Exception as e:
        dlugosc = 0.0

    #bucket
    storage_client = storage.Client()
    bucket_obj = storage_client.bucket(BUCKET)
    blob = bucket_obj.blob(f"mono_{plik.filename}")
    blob.upload_from_filename(mono)

    # Transkrypcja
    client = speech.SpeechClient()
    audio = speech.RecognitionAudio(uri=f"gs://{BUCKET}/mono_{plik.filename}")
    config = speech.RecognitionConfig(
        language_code=jezyk,
        enable_automatic_punctuation=True
    )
    response = client.recognize(config=config, audio=audio)

    teksty = []
    pewnosci = []
    for resp in response.results:
        alt = resp.alternatives[0]
        teksty.append(alt.transcript)
        pewnosci.append(alt.confidence)

    tekst = " ".join(teksty)
    pewnosc = round(sum(pewnosci) / len(pewnosci), 4) if pewnosci else 0.0

    bq = bigquery.Client()
    tabela = bq.get_table("voiceinsights.transkrypcje")
    bq.insert_rows_json(tabela, [{
        "plik": plik.filename,
        "tekst": tekst,
        "data": datetime.now(timezone.utc).isoformat(),
        "dlugosc_s": dlugosc,
        "pewnosc": pewnosc
    }])

    return {
        "plik": plik.filename,
        "transkrypcja": tekst,
        "dlugosc_s": dlugosc,
        "pewnosc": pewnosc
    }

@app.get("/wyniki")
def wyniki():
    bq = bigquery.Client()
    rows = bq.query(
        "SELECT * FROM voiceinsights.transkrypcje ORDER BY data DESC LIMIT 10"
    ).result()
    return [dict(r) for r in rows]



