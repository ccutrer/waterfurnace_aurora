FROM ruby:2.7
WORKDIR /usr/src/app
ENV TTY=/dev/ttyUSB0
ENV MQTT=mqtt://localhost
RUN gem install waterfurnace_aurora

CMD ["ruby", "/usr/local/bundle/bin/aurora_mqtt_bridge $TTY $MQTT"]