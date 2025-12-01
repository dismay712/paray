#!/usr/bin/env sh

APPS_DIR="/apps"

if [ ! -s $APPS_DIR/komari-agent ]; then
    cd $APPS_DIR && \
    curl -o komari-agent -L https://github.com/komari-monitor/komari-agent/releases/latest/download/komari-agent-linux-amd64 && \
    chmod +x komari-agent
fi

if [ ! -s $APPS_DIR/web.js ]; then
    cd $APPS_DIR && \
    curl -o webjs.zip -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip webjs.zip && mv xray web.js && chmod +x web.js && rm webjs.zip
fi

if [ ! -s /etc/supervisor.d/apps.ini ]; then
    sed -e "s#--uuid--#$WEBJS_UUID#g" \
        -e "s#--decryption--#$WEBJS_DECR#g" \
        -i $APPS_DIR/config.json
    AGENT_CMD="$APPS_DIR/komari-agent $KOMARI_ARGS"
    WEBJS_CMD="$APPS_DIR/web.js run -c $APPS_DIR/config.json"
    mkdir -p /etc/supervisor.d && cp $APPS_DIR/apps.ini /etc/supervisor.d/apps.ini && \
    sed -e "s#--agent-cmd--#$AGENT_CMD#g" \
        -e "s#--webjs-cmd--#$WEBJS_CMD#g" \
        -i /etc/supervisor.d/apps.ini
fi

supervisord -c /etc/supervisord.conf
