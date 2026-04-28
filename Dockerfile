FROM --platform=linux/amd64 ubuntu:24.04

# 1. Instalar dependencias mínimas
RUN apt-get update && apt-get install -y \
    curl ca-certificates binaryen build-essential \
    && rm -rf /var/lib/apt/lists/*

# 2. Instalar DFX 0.32.0
ENV DFX_VERSION=0.32.0
ENV DFXVM_INIT_YES=true
RUN curl -fsSL https://sdk.dfinity.org/install.sh | bash
ENV PATH="/root/.local/share/dfx/bin:${PATH}"

WORKDIR /project

# 3. Compilar SOLO el backend para la red IC
ENTRYPOINT ["dfx", "build", "--network", "ic", "vox_populi_backend"]
