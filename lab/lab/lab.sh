#!/usr/bin/env bash
# lab.sh — ponto de entrada único do laboratório (Módulo 9.1)
# Uso: ./lab.sh <comando> [args]
#   subir | checar | baixar
#   incidente iniciar <n>      provoca o incidente n (incidentes/<n>-provocar.sh) e marca T0
#   incidente marcar <n> "..." registra um evento intermediário com a hora
#   incidente recuperado <n>   marca a recuperação e calcula o MTTR
#   incidente reverter <n>     desfaz o incidente (incidentes/<n>-reverter.sh) e checa o ambiente
set -uo pipefail
EV=evidencias; mkdir -p "$EV" incidentes scripts
ts(){ date '+%F %T'; }
epoch(){ date +%s; }
hms(){ printf '%02d:%02d:%02d' $(($1/3600)) $(($1%3600/60)) $(($1%60)); }

cmd="${1:-ajuda}"; shift || true
case "$cmd" in
  subir)  docker compose up -d && echo "Subindo. Rode ./lab.sh checar em ~30 s." ;;
  baixar) docker compose down ;;   # preserva volumes entre os dias; use -v só no fim do curso
  checar) bash scripts/checagem.sh ;;
  incidente)
    sub="${1:?Uso: ./lab.sh incidente <iniciar|marcar|recuperado|reverter> <n>}"; shift
    n="${1:?Informe o número do incidente (1, 2 ou 3)}"; shift || true
    log="$EV/incidente${n}.log"
    case "$sub" in
      iniciar)
        [ -x "incidentes/${n}-provocar.sh" ] || { echo "Falta incidentes/${n}-provocar.sh (crie e dê chmod +x)"; exit 1; }
        echo "T0 $(epoch) $(ts) INICIO incidente ${n}" | tee "$log"
        bash "incidentes/${n}-provocar.sh" 2>&1 | tee -a "$log"
        echo "Falha provocada. Opere a recuperação e rode: ./lab.sh incidente recuperado ${n}" ;;
      marcar)
        echo "MARCA $(epoch) $(ts) ${*:-evento}" | tee -a "$log" ;;
      recuperado)
        [ -f "$log" ] || { echo "Nenhum T0 para o incidente ${n}. Rode 'iniciar' antes."; exit 1; }
        t0=$(awk '/^T0/{print $2; exit}' "$log"); tr=$(epoch)
        echo "TREC $tr $(ts) RECUPERADO" | tee -a "$log"
        echo "MTTR=$(hms $((tr-t0)))" | tee -a "$log"
        echo "Recuperação registrada. MTTR = $(hms $((tr-t0)))."
        echo "Agora reverta ao estado normal: ./lab.sh incidente reverter ${n}" ;;
      reverter)
        [ -x "incidentes/${n}-reverter.sh" ] || { echo "Falta incidentes/${n}-reverter.sh"; exit 1; }
        bash "incidentes/${n}-reverter.sh" 2>&1 | tee -a "$log"
        bash scripts/checagem.sh && echo "Ambiente de volta ao normal (incidente ${n})." ;;
      *) echo "Subcomando inválido: $sub"; exit 1 ;;
    esac ;;
  *) echo "Comandos: subir | checar | baixar | incidente iniciar|marcar|recuperado|reverter <n>" ;;
esac
