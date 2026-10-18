# Catálogo de incidentes

Catálogo **fechado**: cada equipe escolhe **3 incidentes, de 3 famílias diferentes**, e escreve para cada um `incidentes/<n>-provocar.sh` e `<n>-reverter.sh`, seguindo o exemplo resolvido da família Disponibilidade (`incidentes/1-*.sh`).

> Regra: uma reversão escrita e testada para cada falha; tudo na rede `lab91_lab`; critério de parada de 45 min.

## Disponibilidade

_A operação continua quando um nó cai?_

| Incidente               | Como provocar (reversível)                        | Sintoma                                                   | O que prova                         | Como reverter                                                  | O que se mede       |
| ----------------------- | ------------------------------------------------- | --------------------------------------------------------- | ----------------------------------- | -------------------------------------------------------------- | ------------------- |
| Queda do nó primário    | `docker compose stop pg-primary`                  | gerador imprime ESCRITA FALHOU                            | failover para a réplica funciona    | docker compose start pg-primary (recriar réplica se promovida) | RTO do failover     |
| Entrada (proxy) isolada | `docker network disconnect lab91_lab lab-haproxy` | app e gerador não alcançam o banco; o banco está saudável | diagnóstico do tipo “não é o banco” | docker network connect lab91_lab lab-haproxy                   | MTTR do diagnóstico |

## Dados

_Dá para voltar os dados, e quanto se perde?_

| Incidente                   | Como provocar (reversível)                 | Sintoma                                                       | O que prova                                    | Como reverter                   | O que se mede              |
| --------------------------- | ------------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------- | ------------------------------- | -------------------------- |
| Exclusão acidental em massa | `DELETE em pedidos de uma janela de tempo` | linhas somem — e a réplica também perde (replicação ≠ backup) | restauração a partir do backup; medição do RPO | restaurar a base do último dump | RPO real                   |
| Perda do backup local       | `apagar o dump local antes de copiá-lo`    | não há cópia recente na máquina                               | a cópia imutável no MinIO salva                | nova cópia a partir do primário | existência de cópia válida |

## Proteção silenciosa

_A rede de segurança some sem ninguém ver?_

| Incidente                        | Como provocar (reversível)        | Sintoma                               | O que prova                          | Como reverter                     | O que se mede                 |
| -------------------------------- | --------------------------------- | ------------------------------------- | ------------------------------------ | --------------------------------- | ----------------------------- |
| Réplica parada                   | `docker compose stop pg-replica`  | nenhum: o usuário não percebe         | detecção pela checagem de replicação | docker compose start pg-replica   | tempo até detectar sem alerta |
| Arquivamento de WAL interrompido | `quebrar a permissão de /archive` | failed_count sobe em pg_stat_archiver | monitorar o que não dá alerta        | restaurar a permissão de /archive | detecção via pg_stat_archiver |

## Segurança e acesso

_Uma mudança de acesso derruba a operação?_

| Incidente                    | Como provocar (reversível)           | Sintoma                                              | O que prova                               | Como reverter                       | O que se mede                       |
| ---------------------------- | ------------------------------------ | ---------------------------------------------------- | ----------------------------------------- | ----------------------------------- | ----------------------------------- |
| Credencial do banco alterada | `ALTER USER postgres PASSWORD '...'` | gerador falha por autenticação; a porta segue aberta | procedimento de troca controlada de senha | restaurar a senha anterior          | MTTR do diagnóstico de autenticação |
| Tentativa de apagar o backup | `mc rm no bucket com object lock`    | o comando falha                                      | a imutabilidade resiste                   | nada a reverter (a cópia permanece) | confirmação da imutabilidade        |

## Capacidade

_O sistema degrada antes de cair?_

| Incidente                                  | Como provocar (reversível)                | Sintoma                                     | O que prova                                   | Como reverter                | O que se mede                |
| ------------------------------------------ | ----------------------------------------- | ------------------------------------------- | --------------------------------------------- | ---------------------------- | ---------------------------- |
| Esgotamento de conexões                    | `abrir conexões até o limite do banco`    | novas conexões recusadas (too many clients) | degradação antes da queda; limite de conexões | encerrar as conexões abertas | impacto sentido pelo usuário |
| Arquivo de WAL sem espaço (tmpfs limitado) | `preencher o volume limitado de /archive` | arquivamento para; o banco segue gravando   | efeito de capacidade sem derrubar o host      | limpar o volume de /archive  | tempo até detectar e liberar |