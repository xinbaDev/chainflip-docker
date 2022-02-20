FROM ubuntu:20.04 AS base

LABEL maintainer="David Cumps <david@cumps.be>"

RUN apt-get update && \
    apt-get install -y \
    jq \
    wget \
    unzip \
    libssl1.1 \
    ca-certificates && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

ARG CHAINFLIP_VERSION

ENV CHAINFLIP_TAR="chainflip.tar.gz"
ENV CHAINFLIP_RELEASE_URL="https://github.com/chainflip-io/chainflip-bin/releases/download/v${CHAINFLIP_VERSION}-soundcheck/${CHAINFLIP_TAR}" \
    SUBKEY_RELEASE_URL="https://github.com/chainflip-io/chainflip-bin/releases/download/v0.1.0-soundcheck/subkey"

RUN \
    mkdir /chainflip && \
    mkdir /chainflip/config && \
    mkdir /chainflip/chaindata && \
    cd /chainflip && \
    wget $CHAINFLIP_RELEASE_URL && \
    tar xvzf $CHAINFLIP_TAR && \
    rm $CHAINFLIP_TAR && \
    mv chainflip-v$CHAINFLIP_VERSION bin && \
    wget $SUBKEY_RELEASE_URL -P bin && \
    chmod +x bin/*

VOLUME /chainflip/logs \
    /chainflip/config \
    /chainflip/chaindata

FROM base AS engine
ENTRYPOINT [ "" ]
CMD /chainflip/bin/chainflip-engine \
    --config-path /chainflip/config/chainflip.toml

FROM base AS cli
ENTRYPOINT [ "/chainflip/bin/chainflip-cli" ]

FROM base AS node
EXPOSE 9944
EXPOSE 9615
EXPOSE 30333
ENTRYPOINT [ "" ]
CMD /chainflip/bin/chainflip-node \
    --chain soundcheck \
    --base-path /chainflip/chaindata \
    --node-key-file /chainflip/config/node_key \
    --in-peers 500 \
    --out-peers 500 \
    --port 30333 \
    --validator \
    --ws-max-out-buffer-capacity 3000 \
    --unsafe-ws-external \
    --unsafe-rpc-external \
    --prometheus-external \
    --no-private-ipv4 \
    --no-mdns \
    --rpc-cors "all" \
    --rpc-methods "Unsafe" \
    --bootnodes /ip4/165.22.70.65/tcp/30333/p2p/12D3KooW9yoE6qjRG9Bp5JB2JappsU9V5bck1nUDSNRR2ye3dFbU

FROM base AS subkey
ENTRYPOINT [ "/chainflip/bin/subkey" ]

FROM subkey AS keys
ARG NODE_ENDPOINT
ENV NODE_ENDPOINT="${NODE_ENDPOINT}"
ENTRYPOINT [ "" ]
CMD [ ! -f /chainflip/config/keys ]        && /chainflip/bin/subkey generate --output-type json > /chainflip/config/keys ; \
    [ ! -f /chainflip/config/signing_key ] && echo -n $(jq -j -r .secretSeed /chainflip/config/keys | cut -c 3-) > /chainflip/config/signing_key && echo "Generated signing key." ; \
    [ ! -f /chainflip/config/node_key ]    && /chainflip/bin/subkey generate-node-key --file /chainflip/config/node_key 2> /dev/null && echo "Generated node key." ; \
    cat /chainflip/config/chainflip.templ > /chainflip/config/chainflip.toml && echo "node_endpoint = \"${NODE_ENDPOINT}\"" >> /chainflip/config/chainflip.toml ;

# Resulting filesystem:
# /chainflip/bin/chainflip-engine
# /chainflip/bin/chainflip-cli
# /chainflip/bin/chainflip-node
# /chainflip/bin/subkey
# /chainflip/config
# /chainflip/chaindata

# docker build -t chainflip-engine --target engine --build-arg CHAINFLIP_VERSION=0.2.2 .
# docker build -t chainflip-cli --target cli --build-arg CHAINFLIP_VERSION=0.2.2 .
# docker build -t chainflip-node --target node --build-arg CHAINFLIP_VERSION=0.2.2 .
# docker build -t chainflip-subkey --target subkey --build-arg CHAINFLIP_VERSION=0.2.2 .
# docker build -t chainflip-keys --target keys --build-arg CHAINFLIP_VERSION=0.2.2 --build-arg NODE_ENDPOINT=REPLACE .

# docker run --rm -it -v ${PWD}/config:/chainflip/config chainflip-keys
# docker run --rm -it -v ${PWD}/config:/chainflip/config -v ${PWD}/chaindata:/chainflip/chaindata chainflip-node
# docker run --rm -it -v ${PWD}/config:/chainflip/config -v ${PWD}/chaindata:/chainflip/chaindata chainflip-engine

# docker run --rm -it -v ${PWD}/config:/chainflip/config chainflip-cli
