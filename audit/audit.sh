#!/bin/bash
# Ubicación: /audit/audit.sh

WASM_PATH="../.dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD BAJO DEMANDA            \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# 1. Auditoría Backend
if [ -f "$WASM_PATH" ]; then
    HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
    HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend 2>/dev/null | grep "Module hash" | sed 's/.*0x//')
    if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
        BE_STATUS="\033[1;32m[ OK ]\033[0m"
    else
        BE_STATUS="\033[1;31m[ ERROR ]\033[0m"
    fi
    echo -e "Backend: $BE_STATUS"
else
    echo -e "Backend: \033[1;33m[ NO LOCAL WASM ]\033[0m"
fi

# 2. Auditoría Frontend
if [ -f "./get_network_manifest.sh" ]; then
    bash ./get_network_manifest.sh
    if [ -f "assets.hash" ]; then
        LOC_SIG=$(cat assets.hash)
        NET_SIG=$(sha256sum network_assets.manifest | awk '{print $1}')
        if [ "$LOC_SIG" == "$NET_SIG" ]; then
            FE_STATUS="\033[1;32m[ OK ]\033[0m"
        else
            FE_STATUS="\033[1;31m[ ERROR ]\033[0m"
        fi
        echo -e "Frontend: $FE_STATUS"
    else
        echo -e "Frontend: \033[1;33m[ NO LOCAL HASH ]\033[0m"
    fi
fi
echo -e "\033[1;35m===============================================================\033[0m\n"