#!/bin/bash
# Found here https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

case "$(uname -s)" in
  CYGWIN*)
    echo "detected cygwin!"
    export DIR=`cygpath $DIR -w`
    ;;
esac

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac
if [ $machine == "Linux" ]; then
  PYTHON="python3"
else
  PYTHON="python"
fi

export PYTHONPATH="${DIR}:${PYTHONPATH}"
