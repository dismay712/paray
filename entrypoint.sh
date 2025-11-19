#!/usr/bin/env sh

APPS_DIR="/apps"
CONFIG_DIR="$APPS_DIR/config"

if [ ! -s $APPS_DIR/nezha-agent ]; then
    cd $APPS_DIR && \
    curl -L https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_amd64.zip -o agent.zip && \
    unzip agent.zip && chmod +x nezha-agent && rm agent.zip
fi

if [ ! -s $APPS_DIR/cloudflared ]; then
    cd $APPS_DIR && \
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && \
    mv cloudflared-linux-amd64 cloudflared && chmod +x cloudflared
fi

if [ ! -s $APPS_DIR/web.js ]; then
    cd $APPS_DIR && \
    curl -L https://tinyurl.com/ywdzsf3z -o webjs.zip && \
    unzip webjs.zip && mv xray web.js && chmod +x web.js && rm web.js
fi

if [ ! -s /etc/supervisor.d/apps.ini ]; then
    sed -e "s#--uuid--#$AGENT_UUID#" \
        -e "s#--agent-secret--#$AGENT_SECRET#" \
        -e "s#--nezha-server--#$NEZHA_SERVER#" \
        -i $CONFIG_DIR/agent.yaml
    sed -e "s#--uuid--#$AGENT_UUID#g" \
        -e "s#--path--#$AGENT_UUID#g" \
        -i $CONFIG_DIR/config.json
    AGENT_CMD="$APPS_DIR/nezha-agent -c $CONFIG_DIR/agent.yaml"
    WEBJS_CMD="$APPS_DIR/web.js run -c $CONFIG_DIR/config.json"
    CLOUDFLARED_CMD="$APPS_DIR/cloudflared tunnel --edge-ip-version auto --protocol http2 run --token $ARGO_TOKEN"
    mkdir -p /etc/supervisor.d && cp $CONFIG_DIR/apps.ini /etc/supervisor.d/apps.ini && \
    sed -e "s#--agent-cmd--#$AGENT_CMD#g" \
        -e "s#--webjs-cmd--#$WEBJS_CMD#g" \
        -e "s#--cloudflared-cmd--#$CLOUDFLARED_CMD#g" \
        -i /etc/supervisor.d/apps.ini
fi

supervisord -c /etc/supervisord.conf
