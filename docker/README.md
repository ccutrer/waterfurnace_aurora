# Docker
This is a very basic image. Make sure to adjust the ```device``` ```TTY``` and ```MQTT``` settings to fit your configuration.

# To build and run
```
docker build -t ccutrer/waterfurnace_aurora https://github.com/ccutrer/waterfurnace_aurora.git\#main:docker
docker run -d --device=/dev/ttyUSB0 --env TTY=/dev/ttyUSB0 --env MQTT=mqtt://localhost ccutrer/waterfurnace_aurora
```
# To upgrade the build
```
docker build -t ccutrer/waterfurnace_aurora https://github.com/ccutrer/waterfurnace_aurora.git\#main:docker --no-cache
```

# Example docker-compose
```
version: '3.3'

services:
  waterfurnace_aurora:
    container_name: waterfurnace_aurora
    build: 
      context: https://github.com/ccutrer/waterfurnace_aurora.git#main
      dockerfile: ./docker/Dockerfile
    image: ccutrer/waterfurnace_aurora
    devices:
      - '/dev/ttyUSB0'
    environment:
      - TTY=/dev/ttyUSB0
      - MQTT=mqtt://localhost
```

# To run other commands
Before running other commands you need to stop any running waterfurnace_aurora container to free up the serial port.

```docker run --device=/dev/ttyUSB0 -it ccutrer/waterfurnace_aurora <othercommand> <parameters>```
```docker run --device=/dev/ttyUSB0 -it ccutrer/waterfurnace_aurora aurora_fetch --yaml /dev/ttyUSB0 valid ```