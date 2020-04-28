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
