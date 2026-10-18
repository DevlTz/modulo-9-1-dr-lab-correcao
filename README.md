# Módulo 9.1 — Laboratório de DR ponta a ponta

Repositório-base do **Projeto de Testes de Recuperação** da residência Dell Academy
(Instituto Metrópole Digital). Cada equipe **monta** um ambiente de recuperação de
desastres em contêineres, **projeta** incidentes controlados, **recupera** e **mede**,
e fecha com um **plano de melhoria** defendido em banca.

- **Formato:** Aprendizagem Baseada em Projetos (PBL), online.
- **Carga:** 20 h em 5 dias (12 h síncronas + 8 h assíncronas).
- **Turma:** 6 a 7 residentes, 2 equipes de 3 a 4.
- **Cliente fictício:** Loja Potengi (e-commerce 24×7). **Metas:** RTO 30 min, RPO 5 min.

> **Pergunta motriz:** como provar, com evidências, que a operação volta dentro do RTO e
>

## Começo rápido (5 minutos)

Pré-requisitos: **8 GB de RAM livres, 20 GB de disco, Docker Engine 24+ com Compose**
(Linux ou WSL2 recomendados).

```bash
git clone <URL-deste-repo> && cd modulo-9-1-dr-lab/lab
./lab.sh subir            # sobe os 8 serviços
# ~30 s depois, corrija a permissão do arquivo de WAL:
docker compose exec -u root pg-primary chown postgres:postgres /archive
./lab.sh checar           # valida o ambiente (base do aceite do D1)
```

Depois: prepare o backup imutável e a monitoração seguindo
[`docs/01-especificacao-do-ambiente.md`](docs/01-especificacao-do-ambiente.md).

## O que tem aqui

| Pasta                    | Conteúdo                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------------- |
| [`lab/`](lab/)           | Ambiente: `docker-compose.yml`, `lab.sh`, `initdb/`, `haproxy/`, `scripts/`, `incidentes/`               |
| [`docs/`](docs/)         | Documentação do módulo (visão geral, especificação, catálogo, metodologia, guia do instrutor, segurança) |
| [`modelos/`](modelos/)   | Modelos das entregas em `.docx` (E00, D1, D2, D3, R)                                                     |
| [`entregas/`](entregas/) | Onde cada equipe versiona as próprias entregas                                                           |

## O ciclo (resumo)

1. **Construir** o ambiente a partir da especificação (Dia 1).
2. **Projetar** 3 incidentes de 3 famílias e escrever os runbooks de recuperação (Dia 2) → **D1**.
3. **Executar e medir** com o `lab.sh` (Dia 3) → **D2**.
4. **Avaliar e melhorar**: gaps, reteste e banca (Dias 4–5) → **D3**.

## Regras do laboratório (inegociáveis)

1. Toda falha provocada tem **reversão escrita e testada antes** de ser executada.
2. Tudo roda na rede isolada `lab91_lab`; **nada toca produção** nem rede que a alcance.
3. **Critério de parada:** 45 min sem recuperar, ou qualquer efeito fora do laboratório.
4. O incidente de capacidade **não enche o disco do host** (usa limite de conexões ou volume limitado).

Ver [`docs/05-regras-de-seguranca.md`](docs/05-regras-de-seguranca.md).

## Status

Ambiente **validado por sintaxe** (YAML/compose e shell). Rode `./lab.sh subir` uma vez
antes do curso para confirmar na sua máquina (puxar as imagens leva alguns minutos).
