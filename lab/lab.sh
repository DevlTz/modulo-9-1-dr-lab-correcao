#!/usr/bin/env bash
# lab.sh — ponto de entrada único do laboratório (Módulo 9.1)
# Mantém: subir | checar | baixar | incidente iniciar|marcar|recuperado|reverter <n>
# Acrescenta: failover | reintegrar | backup | testar-backup | status | logs | construir
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
EV=evidencias; mkdir -p "$EV" incidentes scripts || exit 1
ts(){ date '+%F %T'; }
epoch(){ date +%s; }
hms(){ printf '%02d:%02d:%02d' "$(($1/3600))" "$(($1%3600/60))" "$(($1%60))"; }
# Preserva o checagem.sh do repositório. O fallback atende ao pacote anterior.
checar(){
  if [ -f scripts/checagem.sh ]; then
    bash scripts/checagem.sh
  else
    bash scripts/check.sh
  fi
}

cmd="${1:-ajuda}"; shift || true
case "$cmd" in
  subir)
    # Único preparo adicional exigido pelas correções: estado do escritor/permissões.
    # No lab original, sem prepare.sh, permanece somente docker compose up -d.
    if [ -f scripts/prepare.sh ]; then bash scripts/prepare.sh || exit $?; fi
    docker compose up -d && echo 'Subindo. Rode ./lab.sh checar em ~30 s.' ;;
  baixar) docker compose down ;; # preserva volumes e arquivos de evidência/controle
  checar) checar ;;
  incidente)
    sub="${1:?Uso: ./lab.sh incidente <iniciar|marcar|recuperado|reverter> <n>}"; shift
    n="${1:?Informe o número do incidente (1, 2 ou 3)}"; shift || true
    case "$n" in 1|2|3) ;; *) echo 'Incidente inválido: use 1, 2 ou 3.' >&2; exit 1;; esac
    log="$EV/incidente${n}.log"
    case "$sub" in
      iniciar)
        [ -x "incidentes/${n}-provocar.sh" ] || {
          echo "Falta incidentes/${n}-provocar.sh (crie e dê chmod +x)"; exit 1;
        }
        # Acrescenta uma rodada sem apagar evidências de execuções anteriores.
        echo "T0 $(epoch) $(ts) INICIO incidente ${n}" | tee -a "$log" || exit $?
        bash "incidentes/${n}-provocar.sh" 2>&1 | tee -a "$log" || exit $?
        echo "Falha provocada. Opere a recuperação e rode: ./lab.sh incidente recuperado ${n}" ;;
      marcar)
        echo "MARCA $(epoch) $(ts) ${*:-evento}" | tee -a "$log" ;;
      recuperado)
        [ -f "$log" ] || { echo "Nenhum T0 para o incidente ${n}. Rode 'iniciar' antes."; exit 1; }
        t0=$(awk '/^T0/{t=$2} END{print t}' "$log"); tr=$(epoch)
        [[ "$t0" =~ ^[0-9]+$ ]] || { echo 'Log sem T0 válido.' >&2; exit 1; }
        ((tr >= t0)) || { echo 'Relógio anterior ao T0; confira o horário.' >&2; exit 1; }
        echo "TREC $tr $(ts) RECUPERADO" | tee -a "$log" || exit $?
        echo "MTTR=$(hms $((tr-t0)))" | tee -a "$log" || exit $?
        echo "Recuperação registrada. MTTR = $(hms $((tr-t0)))."
        echo "Agora reverta ao estado normal: ./lab.sh incidente reverter ${n}" ;;
      reverter)
        [ -x "incidentes/${n}-reverter.sh" ] || { echo "Falta incidentes/${n}-reverter.sh"; exit 1; }
        bash "incidentes/${n}-reverter.sh" 2>&1 | tee -a "$log" || exit $?
        checar && echo "Ambiente de volta ao normal (incidente ${n})." ;;
      *) echo "Subcomando inválido: $sub"; exit 1 ;;
    esac ;;

  # Comandos novos: chamam os scripts auxiliares, sem substituir os incidentes existentes.
  failover) bash scripts/failover.sh "$@" ;;
  reintegrar) bash scripts/rejoin.sh "$@" ;;
  backup) bash scripts/backup-now.sh "$@" ;;
  testar-backup) bash scripts/restore-test.sh "$@" ;;
  validar) bash scripts/check.sh ;;
  status) docker compose ps -a ;;
  logs) docker compose logs --tail=80 "$@" ;;
  construir) docker compose build ;;
  ajuda|-h|--help)
    cat <<'HELP'
Comandos originais:
  ./lab.sh subir
  ./lab.sh checar
  ./lab.sh baixar
  ./lab.sh incidente iniciar <n>
  ./lab.sh incidente marcar <n> "mensagem"
  ./lab.sh incidente recuperado <n>
  ./lab.sh incidente reverter <n>

Comandos adicionados:
  ./lab.sh failover --aceitar-perda-potencial
  ./lab.sh reintegrar <nó-antigo> --descartar-dados-do-no
  ./lab.sh backup
  ./lab.sh testar-backup [sets/.../manifest.json]
  ./lab.sh validar              # checagem adicional das correções
  ./lab.sh status
  ./lab.sh logs [serviço]
  ./lab.sh construir

A reintegração substitui os dados do nó antigo pelo clone do escritor atual.
'incidente recuperado' continua sendo uma marcação manual do operador.
HELP
    ;;
  *) echo "Comando inválido: $cmd. Rode ./lab.sh ajuda."; exit 1 ;;
esac
