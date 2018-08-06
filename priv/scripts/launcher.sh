#!/bin/bash
while getopts s:n: option
do
  case "${option}"
  in
    s) SDPATH=${OPTARG};;
    n) NAME=${OPTARG};;
  esac
done
rm -rdf $NAME;
rebar3 new grispapp name=$NAME dest=$SDPATH;
cd $NAME;
echo -e "{plugins, [\n\t{ rebar3_grisp, {git, \"https://github.com/Laymer/rebar3_grisp.git\"}}\n]}.\n$(cat rebar.config)" > rebar.config;
rebar3 plugins list;
rebar3 new grispapp name=$NAME dest=$SDPATH;
pwd;
cp $NAME/rebar.config ./rebar.config;
cat rebar.config;
cp -r $NAME/src/ ./;
ls ./src;
rm -rdf $NAME/;
ls;
