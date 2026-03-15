# Vox Populi - Sistema de Votación Descentralizado en Internet Computer

Este repositorio contiene el backend de **Vox Populi**, una plataforma de encuestas y votaciones construida íntegramente sobre el **Internet Computer Protocol (ICP)** utilizando el lenguaje **Motoko**.

## Características Técnicas

El proyecto ha sido diseñado siguiendo principios avanzados de ingeniería de software para sistemas distribuidos:

* **Persistencia Ortogonal:** Implementación de `stable var` y `persistent actor` para garantizar que los datos de las votaciones sobrevivan a las actualizaciones del canister (upgrades).
* **Arquitectura Modular:** Separación de responsabilidades en módulos independientes:
    * `Types.mo`: Contratos de datos y DTOs compartidos.
    * `Validation.mo`: Lógica de integridad y reglas de negocio.
    * `Aggregations.mo`: Motor estadístico para el procesamiento de métricas en tiempo real.
* **Optimización de Memoria:** Uso de estructuras de datos eficientes (`List.List`) para lograr una complejidad de inserción **O(1)**, evitando el coste computacional de la copia de arrays inmutables.
* **Seguridad Web3:** * Validación de identidad basada en el `Principal` del firmante (`caller`).
    * Sellado de tiempo (`timestamp`) mediante el consenso de red del IC (`Time.now()`) para evitar manipulaciones externas.

## Estructura del Proyecto

```text
src/vox_populi_backend/
├── main.mo          # Orquestador y API pública del Canister
├── types.mo         # Definiciones de tipos Candid
├── validation.mo    # Reglas de validación de entradas
└── aggregations.mo  # Lógica de cálculo y analítica de datos
