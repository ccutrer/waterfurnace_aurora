FROM ruby:3.3
# Build and install the gem from this checkout, so the image always matches
# the commit/tag it was built from. Build with the repository root as the
# context: docker build -f docker/Dockerfile .
WORKDIR /src
COPY waterfurnace_aurora.gemspec ./
COPY lib ./lib
COPY exe ./exe
RUN gem build waterfurnace_aurora.gemspec && \
    gem install ./waterfurnace_aurora-*.gem && \
    rm -rf /src
ENV TTY=/dev/ttyUSB0
ENV MQTT=mqtt://localhost
WORKDIR /usr/local/bundle/bin/
CMD ruby aurora_mqtt_bridge $TTY $MQTT
