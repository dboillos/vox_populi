FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl ca-certificates binaryen build-essential python3 jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ENV DFX_VERSION=0.32.0
ENV DFXVM_INIT_YES=true
RUN curl -fsSL https://sdk.dfinity.org/install.sh | bash
ENV PATH="/root/.local/share/dfx/bin:${PATH}"

WORKDIR /project