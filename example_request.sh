curl --request POST \
  --url http://:8080/transkrybuj \
  --header 'Content-Type: multipart/form-data' \
  --header 'User-Agent: insomnia/9.3.3' \
  --form jezyk=pl-PL \
  --form 'plik=@/.wav'