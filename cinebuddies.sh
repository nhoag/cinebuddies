#!/bin/bash

set -a ; set -o errexit ; set -o nounset

function usage() {
  cat <<EOF
  Usage: ${0} "entity-1" "entity-2"
  OPTIONS:
    -h        Show usage
    -t        Specify entity type (person, production)
EOF
exit
}

while getopts ":ht:" OPTION; do
  case $OPTION in
    h) usage               ;;
    t) ENT_TYPE=$OPTARG    ;;
  esac
done

shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
  usage
fi

if [[ ! -f $HOME/.cinebuddies ]]; then
  printf 'Enter API token for The Movie Database: '
  read -rs TMDB_TOKEN
  echo
  echo "${TMDB_TOKEN}" \
    > "$HOME/.cinebuddies"
fi

TMDB_AUTH=$(cat "$HOME/.cinebuddies")
TMDB_QUERY_1="${1// /+}"
TMDB_QUERY_2="${2// /+}"

TIMESTAMP=$(date -j -u "+%s")
CINEBUDDIES_TMP_DIR="${TMPDIR}${TIMESTAMP}"
mkdir -p "${CINEBUDDIES_TMP_DIR}"

function hash_gen() {
  md5 -qs "${1}" \
    | sed -E 's/[a-z0-9]{21}$//'
}

function search_results() {
  curl -sS "https://api.themoviedb.org/3/search/multi?api_key=${TMDB_AUTH}&query=${1}"
}

function entity_select() {
  local SELECTION
  SELECTION=1

  while read -r line; do
    if [[ $SELECTION == 1 ]]; then
      echo
      echo "0) exit"
    fi
    echo "$SELECTION) $line"
    ((SELECTION++))
  done <<< "$1"

  ((SELECTION--))
  opt=''
  echo
  while [[ ! `seq -s' ' 1 $SELECTION` =~ $opt ]]; do
    printf 'Select an option from the above list: '
    read -r opt
    for id in `seq -s' ' 1 $SELECTION`; do
      if [[ $opt == $id ]]; then
	ENTITY_INFO=$(sed -n "${opt}p" <<< "$1")
	echo "${ENTITY_INFO}" \
	  > "${CINEBUDDIES_TMP_DIR}/$(hash_gen "${ENTITY_INFO}")"
	break
      elif [[ $opt == 0 ]]; then
	exit
      fi
    done
  done
}

function total_results() {
  jq '.total_results'
}

function results_format() {
  jq -r '.results[] | "\(.id)> " + .media_type + "> " + .release_date + "> " + .title? + .name?' <<< "${1}" \
    | column -t -s'>'
}

function analyze_query_result() {
  TOTAL_RESULTS=$(total_results <<< "$1")
  if [[ $TOTAL_RESULTS -gt 1 ]]; then
    entity_select "$(results_format "$1")"
  elif [[ $TOTAL_RESULTS -eq 0 ]]; then
    # exit because empty result
    exit
  elif [[ -z $TOTAL_RESULTS ]]; then
    # exit because something weird happened
    exit
  else
    ENTITY_INFO=$(results_format "$1")
    echo "${ENTITY_INFO}" \
      > "${CINEBUDDIES_TMP_DIR}/$(hash_gen "${ENTITY_INFO}")"
  fi
}

function get_credits() {
  [[ $1 =~ ^person ]] && ENDPOINT='combined_credits' || ENDPOINT='credits'
  curl -m15 -sS "https://api.themoviedb.org/3/${1}/${ENDPOINT}?api_key=${TMDB_AUTH}" \
    | jq -r '. | .cast? + .crew? | .[] | .name? + "> " + .title?' \
    | sed 's/> /\'$'\n/g' | sort | uniq | grep -Ev '^$'
}

QUERY_ONE_RESULT=$(search_results "${TMDB_QUERY_1}")
analyze_query_result "${QUERY_ONE_RESULT}" "${TMDB_QUERY_1}"
QUERY_TWO_RESULT=$(search_results "${TMDB_QUERY_2}")
analyze_query_result "${QUERY_TWO_RESULT}" "${TMDB_QUERY_2}"

get_credits "$(awk '{print $2"/"$1}' "${CINEBUDDIES_TMP_DIR}/$(ls -1 "${CINEBUDDIES_TMP_DIR}/" | head -1)")" \
  > "${CINEBUDDIES_TMP_DIR}/one"
get_credits "$(awk '{print $2"/"$1}' "${CINEBUDDIES_TMP_DIR}/$(ls -1 "${CINEBUDDIES_TMP_DIR}/" | grep -v one | tail -1)")" \
  > "${CINEBUDDIES_TMP_DIR}/two"

comm -12 "${CINEBUDDIES_TMP_DIR}/one" "${CINEBUDDIES_TMP_DIR}/two"

