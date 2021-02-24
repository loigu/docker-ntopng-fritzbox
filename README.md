# docker-ntopng-fritzbox
network monitoring using ntopng getting data from fritzbox router encapsulated in docker

**build:**
docker image build . -f Dockerfile --build-arg GIT_REV="$(git rev-parse --short HEAD)" --build-arg BUILD_DATE=$(date +”%Y-%m-%dT%H:%M:%SZ%z”) -t sbs:ntopng-fritzbox

**config:**
cp fritzdump.conf.example fritzdump.conf && vim fritzdump.conf

**run:**
docker run -dit --name fritz --env-file fritzdump.conf -p 80:8000 sbs:ntopng-fritzbox

**enjoy:**
chromium-browser http://localhost:8000

**NOTE:**
Fritzbox is not capable of going full-speed when capture is running . We got 1000mbps connection, runs accordingly without capture. As soon as I start the trace the internet speed drops to 20Mb/s...
