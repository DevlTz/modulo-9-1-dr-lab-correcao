# Guia do instrutor

Turma de 6 a 7 residentes, **2 equipes** de 3 a 4. Online, por chamada de vídeo.

## Antes do curso

- Rode `./lab.sh subir` e `./lab.sh checar` uma vez na sua máquina para puxar as imagens

  e confirmar o aceite (ver [`01-especificacao`](01-especificacao-do-ambiente.md)).
- Publique no AVA: os modelos de `modelos/` e o link deste repositório.

## Dia a dia

| Dia    | Seu papel                                                                                                                                                                      |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 (E1) | Lançar a pergunta motriz e a rubrica; formar as equipes; acompanhar a montagem; abrir plantão para quem travar no `./lab.sh subir`.                                            |
| 2 (E2) | Miniaula "anatomia de um incidente"; revisar o desenho dos 3 incidentes de cada equipe (reversão existe? fica no laboratório? parada definida?) antes de autorizar a execução. |
| 3 (E3) | Cada equipe apresenta o D1; depois executa os 3 incidentes em salas separadas com a tela compartilhada; você circula entre as salas.                                           |
| 4      | Assíncrono: tirar dúvidas sobre gaps, matriz e reteste.                                                                                                                        |
| 5 (E4) | Conduzir o reteste e a banca (2 apresentações + perguntas) e a retrospectiva.                                                                                                  |

## Autorizar os incidentes (gate do Dia 2)

Só libere a execução de um incidente quando o par `provocar`/`reverter` estiver escrito e
a reversão testada. Este é o principal controle de segurança do módulo
(ver [`05-regras-de-seguranca`](05-regras-de-seguranca.md)).

## Dinâmica online

- Sem observador externo e sem auditoria cruzada (turma pequena): a **gravação de tela da

  própria equipe** é a evidência.
- Ninguém mexe no notebook de outra equipe; cada equipe roda o próprio `lab.sh`.
- A cronometragem é automática (o `lab.sh` usa o relógio da máquina da equipe), então não

  há cronômetro de mão nem fuso a conciliar na chamada.