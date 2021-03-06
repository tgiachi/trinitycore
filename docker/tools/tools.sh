#!/usr/bin/env bash

# MIT License
# Copyright (c) 2017 Nicola Worthington <nicolaw@tfb.net>

set -Euo pipefail
shopt -s extdebug

# I'm a lazy and indolent 'programmer'.
if ! source /usr/lib/blip.bash ; then
  >&2 echo "Missing dependency 'blip' (https://nicolaw.uk/blip); exiting!"
  exit 2
fi

# Stacktrace on error, with optional dump to shell.
trap 'declare rc=$?; set +xvu
      >&2 echo "Unexpected error executing $BASH_COMMAND at ${BASH_SOURCE[0]} line $LINENO"
      __blip_stacktrace__ >&2
      [[ "${cmdarg_cfg[shell]:-}" == true ]] && drop_to_shell
      exit $rc' ERR

# We only expect to have to use this when the TrinityCore build breaks.
drop_to_shell() {
  {
  echo ""
  echo -e "\033[0;36mFor instructions on map, visual map and movement map" \
          "creation, please see the TrinityCore documentation wiki at" \
          "https://goo.gl/wVUKrK."
  echo ""
  echo -e "\033[0m  => \033[31mInput WoW game client:     \033[1m${cmdarg_cfg[input]}"
  echo -e "\033[0m  => \033[31mOutput map data artifacts: \033[1m${cmdarg_cfg[output]}"
  echo -e "\033[0m  => \033[31mBuild script is:           \033[1m$(cat /proc/$$/cmdline | tr '\000' ' ')"
  echo -e "\033[0m  => \033[31mTools are in:              \033[1m$PWD"
  echo ""
  echo -e "\033[0mType \"\033[31;1mcompgen -v\033[0m\" or \"\033[31;1mtypeset -x\033[0m\" to list variables."
  echo -e "\033[0mType \"\033[31;1mexit\033[0m\" or press \033[31;1mControl-D\033[0m to finish."
  echo ""
  } | fold -w 80 -s
  exec "${BASH}" -i
}

log_error() {
  >&2 echo -e "\033[0;1;31m$*\033[0m"
}

log_notice() {
  echo -e "\033[0;1;33m$*\033[0m"
}

log_success() {
  echo -e "\033[0;1;32m$*\033[0m"
  sleep 3
}

is_directory() {
  [[ -d "${1:-}" ]]
}

_parse_command_line_arguments () {
  cmdarg_info "header" "TrinityCore map extration tools wrapper."
  cmdarg_info "version" "1.0"

  cmdarg_info "author" "Nicola Worthington <nicolaw@tfb.net>."
  cmdarg_info "copyright" "(C) 2017 Nicola Worthington."

  cmdarg_info "footer" \
    "All maps, visual maps (vmaps) and movement maps (mmaps) will be extracted and" \
    "generated by default. Explicitly specifying any of the --maps, --vmaps, --mmaps" \
    "will override the default behaviour, and extract only those speified options." \
    "" \
    "See https://github.com/neechbear/trinitycore, https://neech.me.uk," \
    "https://github.com/neechbear/tcadmin, https://nicolaw.uk/#WoW," \
    "https://hub.docker.com/r/nicolaw/trinitycore," \
    "https://www.youtube.com/channel/UCXDKo2buioQu_cqwIrxODpQ," \
    "https://www.youtube.com/watch?v=JmzZdexSYaM and" \
    "https://github.com/neechbear/trinitycore/blob/master/GettingStarted.md."


  cmdarg 'o:' 'output'  'Output directory for finished map data artifacts' '/artifacts' is_directory
  cmdarg 'i:' 'input'   'Input directory containing WoW game client (and Data sub-directory)' '/World_of_Warcraft' is_directory
  cmdarg 'm'  'maps'    'Extract maps (dbc, maps) from game client'
  cmdarg 'V'  'vmaps'   'Extract visual maps (vmaps) from game client'
  cmdarg 'M'  'mmaps'   'Extrack movement mmaps (mmaps) from game client'
  cmdarg 's'  'shell'   'Drop to a command line shell on errors'
  cmdarg 'v'  'verbose' 'Print more verbose debugging output'

  cmdarg_parse "$@" || return $?
}

directory_min_filecount() {
  declare path="$1"
  declare count="$2"
  [[ $(find "$path" -type f 2>/dev/null | wc -l) -ge $count ]]
}

extract_map_data() {
  declare input="$1"
  declare output="$2"

  pushd "$output"
  mkdir -p "${output%/}"/{mmaps,vmaps}

  # dbc, maps
  if [[ "${cmdarg_cfg[maps]}" == true ]]; then
    mapextractor -i "$input" -o "$output" -e 7 -f 0
    if directory_min_filecount "$output/maps" 5700 && \
       directory_min_filecount "$output/dbc" 240; then
      log_success "Map extraction succeeded."
    else
      log_notice "Map extraction may have failed."
    fi
  fi

  # vmaps
  if [[ "${cmdarg_cfg[vmaps]}" == true ]]; then
    vmap4extractor -l -d "${input%/}/Data"
    vmap4assembler "${output%/}/Buildings" "${output%/}/vmaps"
    if directory_min_filecount "$output/vmaps" 9800; then
      log_success "Visual map (vmap) extraction succeeded."
    else
      log_notice "Visual map (vmap) may have failed."
    fi
  fi

  # mmaps
  if [[ "${cmdarg_cfg[vmaps]}" == true ]]; then
    if [[ ! -d "${output%/}/vmaps" ]]; then
      log_notice "Movement map (mmap) generation requires that visual map" \
                 "(vmap) generation to completed first."
    fi
    mmaps_generator
    if directory_min_filecount "$output/vmaps" 3600; then
      log_success "Movement map (mmap) extraction succeeded."
    else
      log_notice "Movement map (mmap) may have failed."
    fi
  fi

  popd
}

main() {
  # Passthrough if the first argument is executable.
  if [[ $# -ge 1 && -x "${1:-}" ]] && declare cmd="${1:-}"; then
    shift; [[ ! "$cmd" =~ / ]] && cmd="./$cmd"
    exec "$cmd" "$@"
  fi

  # Parse command line options.
  declare -gA cmdarg_cfg=()
  _parse_command_line_arguments "$@" || exit $?

  # Build all maps, vmaps and mmaps is no specific option was specified.
  if [[ -z "${cmdarg_cfg[maps]:-}" && -z "${cmdarg_cfg[vmaps]:-}" && \
        -z "${cmdarg_cfg[mmaps]:-}" ]]; then
    cmdarg_cfg[maps]=true
    cmdarg_cfg[vmaps]=true
    cmdarg_cfg[mmaps]=true
  fi

  # Report command line options and help.
  if [[ -n "${cmdarg_cfg[verbose]}" || -n "${DEBUG:-}" ]]; then
    declare i=""
    for i in "${!cmdarg_cfg[@]}" ; do
      printf '${cmdarg_cfg[%s]}=%q\n' "$i" "${cmdarg_cfg[$i]}"
    done
    unset i
  fi
  if [[ -n "${cmdarg_cfg[help]:-}" ]]; then
    exit 0
  fi

  # Exit early if we cannot find the Data input directory.
  if [[ ! -d "${cmdarg_cfg[input]%/}/Data" ]]; then
    log_error "Could not find Data sub-directory inside input game client" \
              "directory '${cmdarg_cfg[input]}'."
    log_notice "Try copying the Data directory from your World of Warcraft" \
               "game client installation path, into ${cmdarg_cfg[input]}."
    return 1
  fi

  # Generate map data.
  extract_map_data "${cmdarg_cfg[input]}" "${cmdarg_cfg[output]}"
}

main "$@"

