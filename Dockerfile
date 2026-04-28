FROM --platform=linux/amd64 ubuntu:24.04

# 1. Instalar dependencias necesarias
RUN apt-get update && apt-get install -y \
    curl ca-certificates binaryen build-essential \
    && rm -rf /var/lib/apt/lists/*

# 2. Instalar DFX 0.32.0 en modo no interactivo
ENV DFX_VERSION=0.32.0
ENV DFXVM_INIT_YES=true
RUN curl -fsSL https://sdk.dfinity.org/install.sh | bash

# 3. Configurar el PATH
ENV PATH="/root/.local/share/dfx/bin:${PATH}"

WORKDIR /project

# El comando por defecto construye el backend para mainnet
ENTRYPOINT ["dfx", "build", "--network", "ic", "vox_populi_backend"]
