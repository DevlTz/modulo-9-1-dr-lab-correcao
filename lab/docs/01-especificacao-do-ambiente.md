# Especificação do ambiente

A equipe monta o ambiente a partir deste repositório. O instrutor **não** prepara
ambiente por equipe.

## Componentes (10 serviços: 8 de execução contínua + 2 de inicialização/validação)

| Serviço        | Imagem                                     | Porta      | Papel                                                                                    |
| -------------- | ------------------------------------------ | ---------- | ---------------------------------------------------------------------------------------- |
| `archive-init` | postgres:16                                | interna    | One-shot: ajusta o dono do volume `/archive` antes do `pg-primary` subir                 |
| `pg-primary`   | postgres:16                                | interna    | Banco primário, WAL arquivado a cada 60 s                                                |
| `pg-replica`   | postgres:16                                | interna    | Standby em streaming, alvo do failover                                                   |
| `haproxy`      | haproxy:2.9-alpine                         | 5432, 8404 | Entrada única; troca de nó sem mexer na app                                              |
| `gerador`      | postgres:16-alpine                         | —          | Um pedido a cada 5 s (relógio do RPO)                                                    |
| `app`          | adminer:4                                  | 8080       | Interface web sobre o proxy                                                              |
| `minio`        | cgr.dev/chainguard/minio:latest            | 9000, 9001 | Backup imutável (object lock)                                                            |
| `minio-test`   | cgr.dev/chainguard/minio-client:latest-dev | interna    | One-shot: cria o bucket com lock, aplica retenção COMPLIANCE 7d e valida escrita/leitura |
| `backup`       | postgres:16-alpine                         | —          | Dump a cada 15 min em volume local                                                       |
| `kuma`         | louislam/uptime-kuma:2                     | 3001       | Monitoração (mede o MTTD)                                                                |

**Metas (Loja Potengi):** RTO 30 min, RPO 5 min.

## Subir e validar

```bash
cd lab
./lab.sh subir
./lab.sh checar
```

> A permissão do volume de WAL (`/archive`) e o setup do bucket do MinIO (lock +
>
> não é preciso nenhum passo manual de correção de permissão ou de criação de bucket.

### Backup imutável

O bucket com object lock, a retenção e um teste de escrita/leitura são criados
automaticamente pelo serviço `minio-test` ao subir a stack. Para rodar essa validação
isoladamente (ex.: depois de recriar o volume `minio_data`):

```bash
docker compose up minio-test
```

### Monitoração (Uptime Kuma)

Abra <http://localhost:3001>, crie o usuário admin e cadastre 3 monitores com intervalo
de **20 s**: App HTTP (`http://app:8080`), Banco TCP (`haproxy:5432`) e MinIO HTTP
(`http://minio:9000/minio/health/live`).

> A monitoração **não** observa a réplica nem o arquivamento, de propósito: isso vira ???
>

## Critério de aceite (seção 2 do D1)

- [ ] 8 serviços de execução contínua em `running` (incluindo o `backup`); os dois

      serviços one-shot (`archive-init`, `minio-test`) terminam com exit code 0
- [ ] Replicação em streaming; réplica somente leitura
- [ ] Contagem de pedidos cresce no primário e na réplica
- [ ] Arquivamento de WAL sem falhas (`failed_count = 0`)
- [ ] Bucket com object lock e primeiro dump periódico presente
- [ ] 3 monitores verdes no Uptime Kuma

## Parar e limpar

```bash
./lab.sh baixar          # preserva volumes entre os dias
docker compose down -v   # destrói tudo (só no fim do curso)
```