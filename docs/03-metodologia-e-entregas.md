# Metodologia e entregas

Três entregas no curso inteiro, uma por fase. Modelos `.docx` na pasta
[`modelos/`](../modelos/).

## D1 — Plano de Teste de Recuperação (fim do Dia 2)

Ambiente aceito + desenho dos 3 incidentes (família, provocar, reverter, sintoma,
critério de parada, o que se mede) + um runbook de recuperação por incidente (modelo R).

## D2 — Registro de Execução (fim do Dia 3)

Timeline por incidente, RTO/RPO/MTTR medidos (pelo `lab.sh`) ao lado dos acordados,
e o link do vídeo da quebra e recuperação.

## D3 — Relatório Final e Plano de Melhoria (Dia 5)

Sumário que responde à pergunta motriz, resultados acordado × medido, registro de gaps
na matriz risco × esforço, reteste (antes × depois) e rastreabilidade normativa.

## Como executar um incidente (Dia 3)

Sequência fixa 1 → 2 → 3. O `lab.sh` cronometra:

```bash
./lab.sh checar                    # ambiente verde + gravação de tela ligada
./lab.sh incidente iniciar 1       # provoca e marca o T0
# ... a equipe detecta e executa o runbook de recuperação ...
./lab.sh incidente marcar 1 "gerador voltou a gravar"
./lab.sh incidente recuperado 1    # marca o TREC e calcula o MTTR
./lab.sh incidente reverter 1      # desfaz a falha e revalida
```

Tudo fica em `lab/evidencias/incidente<n>.log`.

## Avaliação (100 pontos)

| Componente                  | Pontos |
| --------------------------- | ------ |
| D1 · Plano de Teste         | 25     |
| D2 · Execução               | 30     |
| D3 · Relatório e melhoria   | 25     |
| Atuação individual (papéis) | 10     |
| Banca                       | 10     |

Resultado medido pior que o acordado **não** tira pontos se estiver medido, explicado e
com ação proposta. O que reprova é número sem evidência.
