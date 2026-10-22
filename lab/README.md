# Correções prioritárias — laboratório de recuperação 9.1

Pacote preparado a partir dos sete anexos recebidos. O documento enviado chama-se `gaps.md`, embora o pedido mencione `gaps.txt`. Os anexos são a base desta implementação; o repositório GitHub indicado não pôde ser acessado nesta sessão.

**Situação da entrega:** configurações e scripts implementados, com validações locais. A execução integrada em Docker ainda deve ser feita no laboratório. Não há resultados de RTO/RPO inventados nem declaração de D2 concluída.

## Uso — mesma estrutura do lab original

O `lab.sh` foi ajustado sobre a versão original enviada pelo usuário. Os comandos de incidentes, a pasta `incidentes/` e os logs em `evidencias/` foram preservados. O fluxo de subida em sete etapas foi removido.

```bash
chmod +x lab.sh
./lab.sh subir
# Depois da inicialização:
./lab.sh checar
```

| Comando original | Comportamento mantido |
|---|---|
| `./lab.sh subir` | Executa `docker compose up -d` e orienta a checar depois. |
| `./lab.sh baixar` | Executa `docker compose down`, sem excluir volumes. |
| `./lab.sh checar` | Usa `scripts/checagem.sh`, quando esse arquivo existe. |
| `./lab.sh incidente iniciar 1` | Chama `incidentes/1-provocar.sh` e registra T0. |
| `./lab.sh incidente marcar 1 "mensagem"` | Registra um evento com horário. |
| `./lab.sh incidente recuperado 1` | Registra a declaração manual de recuperação e calcula o tempo desde T0. |
| `./lab.sh incidente reverter 1` | Chama `incidentes/1-reverter.sh` e executa a checagem. |

**Único preparo adicional de `subir`:** se `scripts/prepare.sh` existir, executa-o antes do `docker compose up -d`. Ele prepara permissões e `runtime/active`, necessários às correções de failover, sem alterar uma eleição existente. Não dispara build explícito, backup avulso, restauração ou checagem completa na subida. O próprio Compose pode construir/baixar imagens ausentes e respeita as dependências declaradas, como já ocorre com `up -d`.

| Comando acrescentado | Função |
|---|---|
| `./lab.sh failover --aceitar-perda-potencial` | Executa a promoção controlada. |
| `./lab.sh reintegrar pg-primary --descartar-dados-do-no` | Recria o nó antigo indicado como standby. |
| `./lab.sh backup` | Faz um backup avulso e retoma o agendamento. |
| `./lab.sh testar-backup` | Testa uma restauração remota em banco separado. |
| `./lab.sh validar` | Executa `scripts/check.sh`, a checagem adicional das correções. |
| `./lab.sh status` | Mostra o estado dos containers. |
| `./lab.sh logs backup` | Exibe os logs do serviço. |
| `./lab.sh construir` | Executa build explicitamente quando necessário. |

**Atualização:** copie os arquivos de código para a pasta `lab/` já usada, preservando `incidentes/`, `scripts/checagem.sh`, `runtime/` e todas as evidências. O pacote não substitui os scripts numerados de incidente nem contém um `checagem.sh` que sobrescreva o seu. Se só o pacote anterior estiver instalado, sem `checagem.sh`, `checar` usa `scripts/check.sh` como compatibilidade.

Os scripts auxiliares passam a registrar novos logs em `evidencias/`. Preserve também `evidence/` se já houver logs das versões anteriores; não é necessário renomear nem apagar essa pasta.

Duas correções pequenas no bloco original de incidentes: falha em provocar/reverter retorna erro sem imprimir sucesso; novas rodadas acrescentam logs e `recuperado` usa o último T0. A marcação de recuperação continua manual, como no original; ela não comprova sozinha a recuperação do serviço.

`subir` não promove nem reintegra automaticamente. Ao subir depois de um failover, o Compose pode tentar iniciar o nó antigo, mas `start-db.sh` bloqueia seu retorno como escritor. Confira `status` e `validar`; reintegre o nó antes de declarar a redundância recuperada. A configuração inicial de usuário/monitores do Kuma permanece a cargo da equipe, como previsto no lab.

## 1. Os três gaps escolhidos

| Ordem | Referência no levantamento | Gravidade | Por que foi escolhido | Solução entregue |
|---|---|---|---|---|
| 1 | Item 3: retorno inseguro do primário antigo | Crítica / P0 | Dois escritores podem aceitar alterações divergentes e causar perda silenciosa de dados. | Autorização persistente de um único escritor, bloqueio de inicialização do antigo primário e reintegração por novo `pg_basebackup`. |
| 2 | Item 1: réplica não é failover | Crítica / P0 | O proxy encaminha escritas a um standby somente leitura, sem recuperar o serviço. | Consulta SQL no health check, isolamento comprovado do primário e promoção controlada com teste de escrita. |
| 3 | Observação do item 1 + achados adicionais: cópia imutável inexistente e dump de 15 min | Alta / P1 | A perda do backup local deixa o ambiente sem cópia recuperável no MinIO; o intervalo original também excede a meta de 5 min. | Dump do escritor via HAProxy, envio real com retenção COMPLIANCE, verificação de versões e SHA-256, health check de idade e restauração isolada. |

P0/P1 são prioridades propostas para esta entrega. Os itens 1 e 3 do levantamento estão relacionados, mas têm critérios de aceite distintos: recuperar a escrita durante a queda e impedir que a volta do nó antigo provoque divergência. As correções devem ser aplicadas juntas.

Disco permanece uma pendência **alta e imediata**, especialmente para testes prolongados. Não foi considerado resolvido: limitar logs e manter apenas três conjuntos locais reduz parte do consumo, mas não limita WAL, MinIO ou o disco do host.

## 2. O que muda

### Gap 1 — impedir split-brain e retorno inseguro

- `runtime/active` guarda o escritor autorizado. Começa com `pg-primary`; passa a `pg-replica` após a promoção e é preservado entre reinícios.
- `runtime/fenced-<nó>` identifica o nó isolado. O HAProxy o rejeita, mesmo que responda SQL.
- `start-db.sh` recusa iniciar um banco já promovido se ele não for o escritor autorizado. O primário antigo não volta a aceitar escrita ao reiniciar pelo Compose corrigido.
- `rejoin.sh` reconstrói o antigo nó a partir do escritor atual, verifica o backup físico e exige `pg_is_in_recovery() = true` e streaming.
- Não existe failback automático. Após reintegrar o `pg-primary`, ele permanece standby; a aplicação e o backup continuam usando o HAProxy.

A reintegração **apaga o PGDATA do nó informado**. Por isso exige `--descartar-dados-do-no`. Se houver escritas divergentes a investigar, preserve/exporte esse volume antes de executar. Não use esse script para tentar mesclar históricos: ele não faz reconciliação de dados.

### Gap 2 — failover realmente recupera a escrita

`check-writer.sh` exige simultaneamente:

1. Backend igual ao escritor autorizado.
2. Ausência de marca de isolamento.
3. PostgreSQL fora de recovery e com `transaction_read_only = off`.

Na inicialização, `start-haproxy.sh` gera a configuração efetiva com o backend não eleito administrativamente desabilitado e valida o escritor antes de abrir o listener. Isso evita a janela de inicialização anterior ao primeiro health check. A troca de autorização exige reiniciar o proxy, como já faz `failover.sh`. Se o escritor não responder em aproximadamente 120 s mais o tempo das consultas, a inicialização falha; após corrigir a causa, reinicie o proxy.

O HAProxy usa esse resultado, registra conexões com `log global`/`tcplog`, resolve os endereços pela DNS do Docker e encerra sessões quando um backend é marcado indisponível. Não existe fallback baseado apenas na porta TCP.

`failover.sh` bloqueia operações concorrentes, pausa gerador/backup, bloqueia o tráfego, para o primário e verifica `State.Running=false`. **Só então** promove o standby. Aguarda o WAL já recebido ser aplicado e comprova uma escrita pelo proxy em transação revertida. Se o isolamento não puder ser confirmado, a promoção é cancelada.

A promoção é manual e controlada. Não é eleição distribuída nem failover automático por timeout. A replicação permanece assíncrona: WAL que não chegou à réplica pode ser perdido. O script exige reconhecimento dessa possibilidade e registra LSNs, sem prometer perda zero.

Os dois nós passam a ter os mesmos parâmetros de arquivamento e conexões, e acesso a `/archive`. Foi incluída uma correção auxiliar de arquivamento: publica o WAL atomicamente, aceita repetição apenas com bytes idênticos e recusa sobrescrever WAL divergente. Isso não implementa retenção nem PITR completo.

### Gap 3 — backup remoto verificável

O serviço `backup` deixa de usar `pg-primary` diretamente. Ele consulta o escritor via HAProxy e:

1. Gera dump customizado (`pg_dump -Fc`) em área temporária; falhas não viram backup válido.
2. Valida o catálogo com `pg_restore --list` e exporta roles com `pg_dumpall --roles-only`.
3. Envia dump e roles para chaves únicas no MinIO, com retenção COMPLIANCE de 7 dias e versões identificadas.
4. Consulta a retenção da versão enviada, baixa os bytes e compara SHA-256.
5. Publica o manifesto por último; só então grava `status.json` e registra `BACKUP_OK`.
6. Mantém os três conjuntos locais concluídos mais recentes. Não exclui backups remotos.

`minio-test` cria/configura o bucket e tenta excluir **a versão exata** de um pequeno objeto protegido. O teste só passa se a remoção for negada. Falhas retornam código diferente de zero.

`restore-test.sh` baixa um conjunto exclusivamente do MinIO e restaura em `restore-db`, um PostgreSQL efêmero separado. Compara hashes, verifica a tabela `pedidos` e registra a quantidade e o último horário de pedido. Não altera o banco da aplicação. As roles são preservadas e verificadas, mas não aplicadas automaticamente ao banco de teste; sua importação num DR real requer análise de conflitos com roles já existentes.

**Intervalo e RPO:** há 60 s de espera entre ciclos concluídos. A duração do dump e do upload se soma a esse intervalo; logo, isso não garante RPO de 60 s. O health check reprova quando o início conservador do último snapshot confirmado tem mais de 300 s. A meta de 5 min precisa ser comprovada nos incidentes da D2; um teste de restauração bem-sucedido não basta para provar o RPO.

## 3. Arquivos principais

| Arquivo | Uso |
|---|---|
| `lab.sh` | Interface de operação: subir, baixar, checar e executar recuperação. |
| `docker-compose.yml` | Stack corrigida, com os mesmos nomes de projeto e volumes do anexo. |
| `haproxy/haproxy.cfg` e `haproxy/Dockerfile` | Roteamento por autorização e papel SQL; cliente psql para os checks. |
| `scripts/prepare.sh` | Prepara estado inicial sem sobrescrever eleição anterior. |
| `scripts/failover.sh` | Isolamento, promoção e validação de escrita. |
| `scripts/rejoin.sh` | Reclone do nó antigo e validação do streaming. |
| `scripts/start-db.sh` | Inicialização protegida dos bancos. |
| `scripts/archive-wal.sh` | Arquivamento atômico e idempotente. |
| `backup/backup.py` e `backup/Dockerfile` | Inicialização S3, backups, verificação de idade e teste de restauração. |
| `scripts/check.sh` | Verificações com retorno de erro se escrita, standby ou backup falharem. |
| `scripts/restore-test.sh` | Restaura cópia remota em ambiente efêmero. |
| `docs/D1-D2-D3.md` | Critérios de aceite, incidentes e campos para evidências. |
| `tests/test_safety.py` | Testes locais de falhas, corrupção e isolamento, com dependências simuladas. |

`docker-compose.original.yml` e `haproxy/haproxy.original.cfg` preservam as configurações recebidas para comparação. Os scripts `initdb/01-schema.sql` e `02-hba.sh` foram mantidos funcionalmente iguais.

## 4. Aplicação

### Pré-requisitos

Linux ou WSL2 com Bash, `flock` (util-linux), GNU coreutils, Docker Engine e Compose v2 com suporte a `up --wait`. O build instala `postgresql-client` no HAProxy e `python3/python3-boto3` na imagem de backup. Faça download/build **antes** de isolar a rede do exercício; a execução do lab usa somente os serviços locais. Reserve recursos para o banco de restauração, cujo PGDATA usa tmpfs limitado a 512 MiB.

Foram mantidas as senhas e versões-base do lab para compatibilidade. Não use essas credenciais fora do exercício. As portas publicadas foram restringidas a `127.0.0.1`; acesso remoto ao host deve usar encaminhamento SSH ou uma configuração explicitamente aprovada pela equipe.

### Stack nova

```bash
chmod +x lab.sh
./lab.sh subir
# Após a inicialização e um BACKUP_OK:
./lab.sh validar
./lab.sh testar-backup
```

A subida retorna após a operação do Compose; não equivale a uma checagem completa. Aguarde a inicialização e use `./lab.sh checar`, `./lab.sh validar` e `./lab.sh logs backup`. Execute o teste de restauração depois de um `BACKUP_OK`.

Para o uso diário:

```bash
./lab.sh status
./lab.sh checar
./lab.sh logs backup
./lab.sh baixar
./lab.sh subir
```

### Stack já existente

Planeje uma parada curta, preserve evidências e use somente os volumes do lab:

1. Confirme que o `pg-primary` ainda é o primário válido e `pg-replica` ainda é standby. Se já ocorreu promoção manual, **não** inicialize o estado como `pg-primary`; primeiro identifique qual histórico será mantido.
2. Pare a stack antiga pelo `./lab.sh baixar` original, na pasta original, preservando os volumes. Não rode a stack antiga e a nova em paralelo: ambas usam o projeto `lab91` e os mesmos nomes de containers/volumes.
3. Na pasta deste pacote, execute `chmod +x lab.sh` e `./lab.sh subir`.
4. Acompanhe a subida automática. O projeto `lab91` reutiliza os volumes nomeados originais. Se o projeto original foi iniciado com `-p`/`COMPOSE_PROJECT_NAME` diferente, adapte o nome antes da subida; não presuma que os volumes serão encontrados.
5. Execute `./lab.sh checar` e `./lab.sh testar-backup` antes de realizar novos incidentes.

Os scripts de `initdb` não são reaplicados em volumes existentes. Este pacote pressupõe que a tabela e o usuário replicador do lab original já existem. Não há `docker compose down -v` no procedimento.

**Não volte ao Compose original depois de uma promoção:** ele não respeita o bloqueio persistente e prefere o nó antigo. Para encerrar um exercício, use `./lab.sh baixar`; para voltar ao nome de escritor inicial, primeiro reintegre os nós e realize uma nova troca controlada, registrando o risco da replicação assíncrona.

## 5. Operação dos três cenários

### A. Queda do escritor e recuperação

Em stack inicialmente saudável, provoque apenas a queda controlada do primário:

```bash
# Exemplo: se o incidente 1 da SUA equipe for a queda do primário:
./lab.sh incidente iniciar 1
./lab.sh failover --aceitar-perda-potencial
./lab.sh incidente recuperado 1
```

Os números dos incidentes continuam definidos pelos scripts da sua equipe; o pacote não redefine o que são 1, 2 e 3. O exemplo acima pressupõe que o incidente 1 para o primário. `incidente iniciar` registra T0 antes de chamar o script provocador, como no original. Já o T0 do script de failover representa o início do procedimento de recuperação; não confunda os dois na medição. Antes de marcar `recuperado`, comprove a retomada de escrita.

### B. Retorno do nó antigo

Após o cenário A, tente iniciar o nó antigo:

```bash
docker compose start pg-primary
docker compose logs --tail=30 pg-primary
```

Resultado esperado: inicialização bloqueada e nenhum retorno do tráfego ao nó antigo. Em seguida, se já preservou quaisquer evidências do volume antigo e concorda em substituí-lo:

```bash
./lab.sh reintegrar pg-primary --descartar-dados-do-no
./lab.sh checar
```

Resultado esperado: `pg-replica` continua escritor; `pg-primary` é standby em streaming. Não é necessário voltar imediatamente ao escritor inicial para considerar o serviço recuperado.

### C. Recuperação com cópia remota

```bash
./lab.sh testar-backup
```

O script ignora as cópias locais, baixa versões do MinIO e registra `RESTORE_OK`. Ele remove apenas `restore-db` ao finalizar. Para restaurar uma cópia específica anterior a exclusão lógica, informe o manifesto:

```bash
./lab.sh testar-backup sets/IDENTIFICADOR-DO-BACKUP/manifest.json
```

Substitua pelo `id` real mostrado no log `BACKUP_OK`. Não escolha automaticamente o conjunto mais recente depois de um `DELETE`: ele pode já conter a exclusão. O teste padrão com a cópia mais recente é um teste de capacidade de restauração, não uma escolha automática de ponto limpo.

### Se a troca for interrompida

Os scripts falham de forma conservadora: o proxy pode ficar parado e `runtime/active` pode ficar `none`. Não apague a pasta `runtime`, não execute a configuração antiga e não reinicie ambos como primários.

Inspecione `evidencias/failover-*.log`, `./lab.sh status`, `runtime/active`, os arquivos `fenced-*` e `pg_is_in_recovery()` em cada banco. Identifique se a promoção ocorreu e qual nó contém o histórico a manter. Só reabra o proxy depois de confirmar que o outro nó está parado/isolado. Falhas de promoção intermediárias exigem decisão do operador; não há rollback cego para o primário antigo.

## 6. Limitações e próximos gaps

- **Disco (alta):** arquivo WAL continua sem retenção. Sob atividade, `archive_timeout=60` pode produzir aproximadamente um segmento de 16 MiB/min; isso corresponde a 22,5 GiB/dia. Não é uma taxa fixa em banco ocioso. MinIO também acumula objetos, e COMPLIANCE de 7 dias impede apagar antecipadamente suas versões pela API. Antes de testes longos, dimensione volume dedicado/quota e política de expiração compatível com retenção. Não use `find -mtime ... -delete` indiscriminadamente em WAL.
- **Estimativa de backup:** 1 dump por minuto dá até aproximadamente 10.080 dumps em 7 dias. Multiplique pelo tamanho médio observado, some roles, metadados, versões, WAL e margem. O ciclo real inclui tempo de execução. O limite individual de 256 MiB no uploader não é quota do volume.
- **PITR não implementado:** os dumps permitem recuperar snapshots lógicos. O arquivo WAL, isoladamente, não é uma solução de recuperação por horário sem backup físico base e cadeia completa de WAL. O basebackup usado em rejoin não é publicado como base histórica de PITR.
- **Um host:** MinIO, bancos e volumes continuam no mesmo domínio físico de falha. Object Lock não protege contra exclusão do volume pelo administrador do host nem perda do disco. Uma cópia off-host é melhoria posterior.
- **Fencing do lab:** depende de um Docker daemon acessível, dos scripts e do diretório persistente de controle. Não substitui STONITH externo/quórum para clusters distribuídos. Um administrador que contorne o launcher ou publique os bancos diretamente pode quebrar essa proteção.
- **Monitoramento:** os checks melhoram a detecção, mas não configuram canais de alerta ou todos os monitores do Kuma. Healthcheck `unhealthy` não dispara, por si só, recuperação automática.
- **RPO:** replicação assíncrona e falhas prolongadas do backup podem ultrapassar 5 min. O código detecta idade excessiva; não elimina esse risco. Meça a perda efetiva.
- **Compatibilidade:** as imagens `latest` do MinIO e tags de versão foram herdadas dos anexos. Fixar digests e validar a versão real do cliente/servidor faz parte da homologação. Nesta sessão não há Docker para execução integrada. O log enviado pelo usuário mostra que as imagens customizadas foram construídas em sua máquina, mas a subida parou ao buscar `postgres:16`, com `error getting credentials`; isso não confirma o funcionamento integrado.
- **Credenciais:** acesso administrativo ao PostgreSQL e ao MinIO permanece como no lab. Separar permissões e usar secrets fica como melhoria posterior.

Uma inconsistência do levantamento foi corrigida na análise: **a especificação anexada já usa Uptime Kuma `:2`**, igual ao Compose; portanto, a divergência `:1` versus `:2` não se sustenta nesses anexos. A especificação recebida declara RTO de 30 min e RPO de 5 min. A observação de disco de 20 GB está no levantamento, mas esse tamanho não aparece na especificação anexada.

## 7. Validação realizada nesta entrega

- Parsing YAML e verificação dos caminhos de bind mounts/builds.
- Sintaxe Bash dos scripts e compilação do Python.
- 12 testes de segurança: rejeição de backup vazio, corrupção e retenção inadequada; preservação do status anterior em falhas; manifesto por último; rejeição de snapshot vencido; WAL atômico/idempotente; promoção bloqueada sem isolamento e permitida somente depois dele.

Além disso, passaram 12 testes de compatibilidade da interface: subida simples, funcionamento sem o preparo opcional, `down` sem excluir volumes, preferência pela checagem original, propagação de falhas, preservação dos logs, uso do último T0, reversão e encaminhamento dos argumentos. **Total: 24 testes locais aprovados.**

Os testes de S3, PostgreSQL e Docker usam simulações onde indicado; **não provam** compatibilidade das imagens nem o comportamento integrado. `docker compose config`, `haproxy -c`, build, streaming, upload real, Object Lock e restore real ficam como gates de execução no lab. Veja `docs/D1-D2-D3.md`.

Para repetir os testes locais:

```bash
python3 -m unittest discover -s tests -v
```

## Referências técnicas

- PostgreSQL 16 — failover e necessidade de impedir retorno do escritor antigo: https://www.postgresql.org/docs/16/warm-standby-failover.html
- PostgreSQL 16 — `pg_basebackup`: https://www.postgresql.org/docs/16/app-pgbasebackup.html
- PostgreSQL 16 — `pg_verifybackup` e seus limites: https://www.postgresql.org/docs/16/app-pgverifybackup.html
- PostgreSQL 16 — dump lógico e objetos globais: https://www.postgresql.org/docs/16/app-pgdump.html
- PostgreSQL 16 — arquivamento contínuo e PITR: https://www.postgresql.org/docs/16/continuous-archiving.html
- HAProxy 2.9 — `external-check`, variáveis do servidor e `on-marked-down`: https://docs.haproxy.org/2.9/configuration.html
- API S3/Boto3 — versões, Content-MD5 e retenção de objetos: https://docs.aws.amazon.com/boto3/latest/reference/services/s3/client/put_object.html
