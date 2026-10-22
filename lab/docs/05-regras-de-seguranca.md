# Regras de segurança do laboratório (inegociáveis)

1. **Reversão primeiro.** Todo `incidentes/<n>-provocar.sh` só é executado depois que o

   `incidentes/<n>-reverter.sh` correspondente está escrito e testado.
2. **Isolamento.** Tudo roda na rede `lab91_lab`. Nenhum comando aponta para produção,

   nem para qualquer serviço ou rede fora do próprio laboratório.
3. **Critério de parada.** 45 minutos sem recuperar, ou qualquer efeito fora do

   laboratório, encerra o incidente — rode `./lab.sh incidente reverter <n>`.
4. **Capacidade sem risco ao host.** O incidente da família Capacidade usa limite de

   conexões ou um volume limitado; **nunca** encha o disco da máquina.
5. **Snapshot antes.** `./lab.sh baixar` (ou um snapshot da VM) antes de cada incidente,

   para poder repetir.

Estas regras são o enquadramento de **teste de recuperação controlado**: a equipe provoca
falhas reversíveis no próprio ambiente para medir e melhorar a recuperação — não há alvo
externo nem técnica ofensiva.
