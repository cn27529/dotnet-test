#build to go on create image from Dockerfile
docker build --pull -t aspnetmvcapp .

#run
docker run --name aspnetmvcapp_sample -it -p 8000:80 aspnetmvcapp

#restart and stop
docker restart aspnetmvcapp_sample
docker stop aspnetmvcapp_sample

#remove
docker rm aspnetmvcapp_sample
