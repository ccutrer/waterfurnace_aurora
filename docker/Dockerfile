FROM ruby:2.7
ENV TTY=/dev/ttyUSB0
ENV MQTT=mqtt://localhost
RUN gem install waterfurnace_aurora
CMD ruby aurora_mqtt_bridge $TTY $MQTT