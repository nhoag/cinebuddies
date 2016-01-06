#!/bin/bash

set -a ; set -o errexit ; set -o nounset

# http://stackoverflow.com/questions/592620/check-if-a-program-exists-from-a-bash-script
hash gdate 2>/dev/null || { echo >&2 "I require gdate but it's not installed. Aborting."; exit 1; }

function usage() {
  cat <<EOF
  Usage: ${0} [OPTIONS] "entity-1" ["entity-2"]
  OPTIONS:
    -h        Show usage
    -t        Specify entity type (person, movie, tv)
EOF
exit
}

ENT_TYPE=''

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

QUERIES=0
if [[ ! -z "${TMDB_QUERY_1}" ]]; then
  ((QUERIES++))
fi
if [[ ! -z "${TMDB_QUERY_2}" ]]; then
  ((QUERIES++))
fi

if [[ ! ${ENT_TYPE} =~ ^(person|movie|tv)?$ ]]; then
  >&2 echo "Type option must be one of movie, person, or tv"
  exit
fi

function timestamp_create() {
  gdate +%s%6N
}

TIMESTAMP=$(timestamp_create)
CINEBUDDIES_TMP_DIR="${TMPDIR}${TIMESTAMP}"
mkdir -p "${CINEBUDDIES_TMP_DIR}"

function search_results() {
  curl -sS "https://api.themoviedb.org/3/search/multi?api_key=${TMDB_AUTH}&query=${1}"
}

function entity_select() {
  local SELECTION
  SELECTION=1
  SELECT_LINES=$(wc -l <<< "$1" \
    | sed 's/^ *//')

  if [[ $SELECT_LINES -gt 1 ]]; then
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
            > "${CINEBUDDIES_TMP_DIR}/$(timestamp_create)"
          break
        elif [[ $opt == 0 ]]; then
          exit
        fi
      done
    done
  else
    echo "${1}" \
      > "${CINEBUDDIES_TMP_DIR}/$(timestamp_create)"
  fi
}

function total_results() {
  jq '.total_results'
}

function results_format() {
  jq -r '.results[] | "\(.id)> " + .media_type + "> " + .release_date + "> " + .title? + .name?' <<< "${1}" \
    | column -t -s'>' \
    | awk -v entity_type=$ENT_TYPE '{
        if (entity_type == "") {
          print
        } else if ($2 == entity_type) {
          print
        }
      }'
}

function analyze_query_result() {
  TOTAL_RESULTS=$(total_results <<< "$1")
  if [[ $TOTAL_RESULTS -gt 1 ]]; then
    entity_select "$(results_format "$1")"
  elif [[ $TOTAL_RESULTS -eq 0 ]]; then
    # exit because empty result
    >&2 echo "Empty result for query"
    exit
  elif [[ -z $TOTAL_RESULTS ]]; then
    # exit because something weird happened
    >&2 echo "There was a problem with the request"
    exit
  else
    ENTITY_INFO=$(results_format "$1")
    echo "${ENTITY_INFO}" \
      > "${CINEBUDDIES_TMP_DIR}/$(timestamp_create)"
  fi
}

function get_credits() {
  [[ $1 =~ ^person ]] && ENDPOINT='combined_credits' || ENDPOINT='credits'
  curl -m15 -sS "https://api.themoviedb.org/3/${1}/${ENDPOINT}?api_key=${TMDB_AUTH}" \
    | jq -r '. | .cast? + .crew? | .[] | .name? + "> " + .title?' \
    | sed 's/> /\'$'\n/g' \
    | sort \
    | uniq \
    | grep -Ev '^$'
}

# Get credits for all seasons in a TV series
# Series credits
# curl -sS https://api.themoviedb.org/3/${1}/credits?api_key=${TMDB_AUTH} | jq -r '. | .cast? + .crew? | .[] | .name? + "> " + .title?'
# Season IDs
# curl -sS https://api.themoviedb.org/3/${1}?api_key=${TMDB_AUTH} | jq -r '.seasons | .[] | .season_number'
# Season credits
# curl -sS https://api.themoviedb.org/3/${1}/season/${SEASON}/credits?api_key=${TMDB_AUTH} | jq -r '.seasons | .[] | .season_number'

function build_entity_data() {
  QUERY_RESULT=$(search_results "${1}")
  analyze_query_result "${QUERY_RESULT}" "${1}"
}

function stash_entity_data() {
  ENTITY_FILE=$(ls -1 "${CINEBUDDIES_TMP_DIR}/" \
    | grep -Ev '^[1-2]$' \
    | sed -n "${FILE_ID}p")
  get_credits "$(awk '{print $2"/"$1}' "${CINEBUDDIES_TMP_DIR}/${ENTITY_FILE}")" \
    > "${CINEBUDDIES_TMP_DIR}/${FILE_ID}"
}

FILE_ID=1
for i in $(seq 1 $QUERIES); do
  QUERY_ID="TMDB_QUERY_$i"
  build_entity_data "${!QUERY_ID}"
  stash_entity_data
  ((FILE_ID++))
done

if [[ $QUERIES == 2 ]]; then
  comm -12 "${CINEBUDDIES_TMP_DIR}/1" "${CINEBUDDIES_TMP_DIR}/2"
else
  cat "${CINEBUDDIES_TMP_DIR}/1"
fi

