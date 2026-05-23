#!/bin/bash

PROJECT_ID=$(gcloud config get project)
ZONE="europe-west1-b"
VM="voiceinsights-vm"
BUCKET="voiceinsights-bucket-${PROJECT_ID}"
REPO="https://github.com/Desu-potato/voices.git"

# API
gcloud services enable \
  compute.googleapis.com \
  speech.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com

# bucket
gcloud storage buckets create gs://${BUCKET} \
  --location=europe-west1 2>/dev/null || echo "bucket już istnieje"

# bigquery
bq mk voiceinsights 2>/dev/null || echo "dataset już istnieje"
bq mk --table voiceinsights.transkrypcje \
  plik:STRING,tekst:STRING,data:TIMESTAMP,dlugosc_s:FLOAT64,pewnosc:FLOAT64 \
  2>/dev/null || echo "tabela już istnieje"

# uprawnienia
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/bigquery.jobUser" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/storage.objectAdmin" --quiet

# vm
gcloud compute instances create $VM \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --scopes=cloud-platform \
  --image-family=debian-12 \
  --image-project=debian-cloud

echo "czekam aż VM wstanie..."
sleep 30

# instalacja zależności na vm
gcloud compute ssh $VM --zone=$ZONE --command="
  sudo apt-get update -q &&
  sudo apt-get install -y ffmpeg python3-pip git &&
  pip install fastapi uvicorn google-cloud-speech \
    google-cloud-bigquery google-cloud-storage \
    python-multipart --break-system-packages &&
  echo 'export PATH=\$PATH:\$HOME/.local/bin' >> ~/.bashrc
"

# klonowanie repo
gcloud compute ssh $VM --zone=$ZONE --command="
  git clone ${REPO} ~/app
"

# firewall
gcloud compute firewall-rules create allow-8080 \
  --allow=tcp:8080 \
  --target-tags=voiceinsights \
  --description="VoiceInsights API" 2>/dev/null || echo "firewall już istnieje"

gcloud compute instances add-tags $VM \
  --tags=voiceinsights \
  --zone=$ZONE

# start api
gcloud compute ssh $VM --zone=$ZONE --command="
  export PATH=\$PATH:\$HOME/.local/bin
  export BUCKET=${BUCKET}
  cd ~/app
  nohup uvicorn main:app --host 0.0.0.0 --port 8080 > ~/api.log 2>&1 &
  echo 'API uruchomione'
"

IP=$(gcloud compute instances describe $VM --zone=$ZONE format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo ""
echo "=============================="
echo "http://${IP}:8080"
echo "http://${IP}:8080/docs"
echo "=============================="

