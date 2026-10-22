# lab/ — o ambiente

`lab.sh` é o ponto de entrada único.

```bash
./lab.sh subir            # docker compose up -d
./lab.sh checar           # checagem pré-voo (grava em evidencias/)
./lab.sh incidente iniciar <n>      # provoca incidentes/<n>-provocar.sh e marca o T0
./lab.sh incidente marcar <n> "..." # registra um evento
./lab.sh incidente recuperado <n>   # marca a recuperação e calcula o MTTR
./lab.sh incidente reverter <n>     # desfaz (incidentes/<n>-reverter.sh) e revalida
./lab.sh baixar           # docker compose down (preserva volumes)
```

| Caminho | O que é |
|---|---|
| `docker-compose.yml` | Os 8 serviços do cenário |
| `initdb/` | Esquema da Loja Potengi e liberação da replicação |
| `haproxy/haproxy.cfg` | Entrada única; réplica como backup |
| `scripts/checagem.sh` | Checagem pré-voo (base do aceite do D1) |
| `incidentes/1-*.sh` | Exemplo resolvido (família Disponibilidade) |
| `incidentes/TEMPLATE-*.sh` | Esqueleto para os incidentes 2 e 3 |
| `incidentes/CATALOGO.md` | As 5 famílias de incidente |
| `evidencias/` | Logs e saídas geradas pelo `lab.sh` (não versionados) |
