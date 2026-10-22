# Visão geral do módulo

O Módulo 9.1 é um **projeto único**: a turma não assiste a aulas isoladas; cada equipe
entrega um laboratório de recuperação de desastres **funcionando, testado e defendido**.

## As três fases (ciclo do NIST SP 800-84)

| Fase                 | Dias | Entrega                                      | Base normativa                                           |
| -------------------- | ---- | -------------------------------------------- | -------------------------------------------------------- |
| Planejar e construir | 1–2  | **D1** · Plano de Teste de Recuperação       | ISO 22301 8.5 · 22317 · NIST SP 800-34 §3.5 · 800-84     |
| Executar e medir     | 3    | **D2** · Registro de Execução                | NIST SP 800-84 · 800-61 · ISO/IEC 27002 8.13 · 27035     |
| Avaliar e melhorar   | 4–5  | **D3** · Relatório Final e Plano de Melhoria | ISO 22301 cl. 9 e 10 · NIST SP 800-84 (improvement plan) |

## Calendário de 5 dias

| Dia | Síncrono | Assíncrono | O que acontece                                  |
| --- | -------- | ---------- | ----------------------------------------------- |
| 1   | E1 · 3 h | 1 h        | Kickoff; montar o ambiente; escolher 3 famílias |
| 2   | E2 · 3 h | 2 h        | Projetar incidentes e runbooks → **D1**         |
| 3   | E3 · 3 h | 2 h        | Executar, recuperar e medir → **D2**            |
| 4   | —        | 3 h        | Gaps, plano de melhoria e relatório             |
| 5   | E4 · 3 h | —          | Reteste e banca final → **D3**                  |

Total: 12 h síncronas + 8 h assíncronas = **20 h**.

## Papéis (giram a cada dia)

- **Coordenação / líder de crise** — conduz decisões, controla o tempo, aciona a parada.
- **Execução técnica** — opera o `lab.sh`, os scripts de incidente e a recuperação.
- **Cronometragem e evidências** — confere as marcas do `lab.sh`, grava a tela, guarda logs.
- **Documentação e comunicação** — redige as entregas e submete no AVA.

Quem planeja/provoca a falha e quem recupera são **chapéus da mesma equipe**, em momentos
diferentes. É **teste de recuperação controlado** — vocabulário das normas, não red/blue team.
