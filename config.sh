#!/bin/bash

PROJECT_ID=$(gcloud config get project)
ZONE="europe-west1-b"
VM="voiceinsights-vm"
BUCKET="voiceinsights-bucket-${PROJECT_ID}"

gcloud compute instances create $VM \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --scopes=cloud-platform \
  --image-family=debian-12 \
  --image-project=debian-cloud

sleep 30

gcloud compute ssh $VM --zone=$ZONE --command="
  sudo apt-get update -q &&
  sudo apt-get install -y ffmpeg python3-pip &&
  pip install fastapi uvicorn google-cloud-speech \
    google-cloud-bigquery google-cloud-storage \
    python-multipart --break-system-packages &&
  echo 'export PATH=\$PATH:\$HOME/.local/bin' >> ~/.bashrc
"

gcloud compute scp ./main.py $VM:~ --zone=$ZONE

gcloud compute firewall-rules create allow-8080 \
  --allow=tcp:8080 \
  --target-tags=voiceinsights 2>/dev/null || true

gcloud compute instances add-tags $VM \
  --tags=voiceinsights \
  --zone=$ZONE

gcloud compute ssh $VM --zone=$ZONE --command="
  export PATH=\$PATH:\$HOME/.local/bin
  export BUCKET=$BUCKET
  nohup uvicorn main:app --host 0.0.0.0 --port 8080 > ~/api.log 2>&1 &
"

IP=$(gcloud compute instances describe $VM \
  --zone=$ZONE \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "http://${IP}:8080"