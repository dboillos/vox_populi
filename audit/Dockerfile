# Eliminamos el --platform fijo para que use la nativa del host
FROM ubuntu:24.04

# Instalar dependencias para DFX, Python (para el script) y curl/jq para red
RUN apt-get update && apt-get install -y \
    curl ca-certificates binaryen build-essential python3 jq \
    && rm -rf /var/lib/apt/lists/*

# Instalar DFX 0.32.0
ENV DFX_VERSION=0.32.0
ENV DFXVM_INIT_YES=true
RUN curl -fsSL https://sdk.dfinity.org/install.sh | bash
ENV PATH="/root/.local/share/dfx/bin:${PATH}"

WORKDIR /project
# Eliminamos el ENTRYPOINT para que el script decida qué ejecutar
