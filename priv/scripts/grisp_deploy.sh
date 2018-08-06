#!/bin/bash
if ! [ $(id -u) = 0 ]; then
   echo "The script need to be run using SUDO" >&2
   exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

contains () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

while getopts s:a:n option
do
  case "${option}"
  in
    s) SDPATH=${OPTARG};;
    a) APPLICATION=${OPTARG};;
    n) NAME=${OPTARG};;
  esac
done

while [[ true ]]
do
  ((counter++));
  if [[ -d $SDPATH ]]; then
      cd $APPLICATION && rebar3 compile;
      if [[ -n $NAME ]]; then
        rebar3 grisp deploy --relname $NAME --relvsn 0.1.0;
      else
        cd $APPLICATION/src;
        FILES=();
        index=0;
        for file in *[a-z].erl; do
            appname=$(echo "${file}" | sed 's/_//' | sed 's/-//' | sed 's/\.//' | sed 's/erl//' | sed 's/sup//');
            contains "${appname}" "${FILES[@]}";
            if [[ $? -eq 1 ]]; then
              FILES[$index]="${appname}";
              ((index++));
            fi
        done
        cd $APPLICATION && rebar3 grisp deploy --relname "${FILES[0]}" --relvsn 0.1.0;
      fi
      if [ "$(uname)" == "Darwin" ]; then
          diskutil unmount $SDPATH;
          retval=$?;
          if [[ $retval -eq 1 ]]; then
            echo -e "${RED}unmount failed, cleaning PIDs...${NC}";
            pids=( $(fuser -c $SDPATH) );
            sudo kill -9 ${pids[*]};
            echo "retrying unmount...";
            sudo diskutil unmount $SDPATH;
            sudoretval=$?;
            while [[ $sudoretval -ne 0 ]]; do
              echo -e "${ORANGE}forcing unmount${NC}";
              pids=( $(fuser -c $SDPATH) );
              sudo kill -9 ${pids[*]};
              sudo diskutil unmount $SDPATH;
              sudoretval=$?;
            done
            echo -e "${ORANGE}unmount success with sudo privilegies${NC}";
            echo -e "${GREEN}Application deployed to SD Card, ready to remove ... ${NC}"
          elif [[ $retval -eq 0 ]]; then
            echo "unmount success";
            echo -e "${GREEN}Application deployed to SD Card, ready to remove ... ${NC}"
          fi
      elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
          umount $SDPATH;
          retval=$?;
          if [[ $retval -eq 1 ]]; then
            echo -e "${RED}unmount failed, cleaning PIDs...${NC}";
            pids=( $(fuser -c $SDPATH) );
            sudo kill -9 ${pids[*]};
            echo "retrying unmount...";
            sudo umount $SDPATH;
            sudoretval=$?;
            while [[ $sudoretval -ne 0 ]]; do
              echo -e "${ORANGE}forcing unmount${NC}";
              pids=( $(fuser -c $SDPATH) );
              sudo kill -9 ${pids[*]};
              sudo umount $SDPATH;
              sudoretval=$?;
            done
            echo -e "${ORANGE}unmount success with sudo privilegies${NC}";
            echo -e "${GREEN}Application deployed to SD Card, ready to remove ... ${NC}"
          elif [[ $retval -eq 0 ]]; then
            echo "unmount success";
            echo -e "${GREEN} ===> Application deployed to SD Card, ready to remove ... ${NC}"
          fi
      elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
          echo "windows" >&2
          exit 1
      elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW64_NT" ]; then
          echo "windows" >&2
          exit 1
      fi
  else
      sleep 1;
  fi
done
