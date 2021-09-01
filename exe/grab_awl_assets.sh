#!/bin/bash

mkdir -p html
mkdir -p html/css
mkdir -p html/js
mkdir -p html/images

IP=${1:-172.20.10.1}

curl http://$IP/ > html/index.htm
curl http://$IP/config.htm > html/config.htm
curl http://$IP/favicon.ico > html/favicon.ico
curl http://$IP/css/index.css > html/css/index.css
curl http://$IP/css/phone.css > html/css/phone.css
curl http://$IP/js/indexc.js > html/js/indexc.js
curl http://$IP/js/configc.js > html/js/configc.js
curl http://$IP/images/aurora.png > html/images/aurora.png
curl http://$IP/images/back.png > html/images/back.png
curl http://$IP/images/cfailed.png > html/images/cfailed.png
curl http://$IP/images/cgood.png > html/images/cgood.png
curl http://$IP/images/cidle.png > html/images/cidle.png
