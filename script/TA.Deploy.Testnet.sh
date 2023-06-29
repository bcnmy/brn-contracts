#!/bin/bash

dir=$(dirname $0)

source $dir/../.env

forge script \
    --broadcast \
    --rpc-url $SIMULATION_RPC_URL \
    -vvv \
    $dir/TA.Deployment.s.sol